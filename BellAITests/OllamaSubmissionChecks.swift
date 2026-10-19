// Standalone checks: run with scripts/check-ollama.sh. No real API calls or keys.
import Foundation

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var capturedRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.capturedRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class StubService: BellAIService {
    var requests: [ChatRequest] = []
    var shouldFail = false
    var shouldCancel = false
    func send(_ request: ChatRequest) async throws -> ChatResponse {
        requests.append(request)
        if shouldCancel { throw CancellationError() }
        if shouldFail { throw BellAIServiceError.http(429) }
        return ChatResponse(model: request.model, message: ChatMessage(role: "assistant", content: "Mock reply"), done: true)
    }
}

@MainActor
final class DelayedService: BellAIService {
    var continuation: CheckedContinuation<ChatResponse, Error>?
    func send(_ request: ChatRequest) async throws -> ChatResponse {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
}

@main
struct OllamaSubmissionChecks {
    @MainActor
    static func main() async throws {
        let stub = StubService()
        let viewModel = ChatViewModel(service: stub, model: "test-model")
        precondition(!viewModel.validateAndStoreRequest(" \n "))
        precondition(viewModel.pendingRequest == nil && !viewModel.isSubmitting)
        precondition(!viewModel.validateAndStoreRequest(String(repeating: "a", count: 4_001)))
        precondition(viewModel.validateAndStoreRequest("  Hello Bell!\n"))
        precondition(viewModel.pendingRequest?.messages.first?.content == "Hello Bell!")
        precondition(!viewModel.validateAndStoreRequest("duplicate"))
        await viewModel.submitStoredRequest()
        precondition(stub.requests.count == 1 && !viewModel.isSubmitting)
        precondition(viewModel.errorMessage == nil)
        precondition(viewModel.response?.message.content == "Mock reply")
        precondition(viewModel.responseError == nil)
        precondition(viewModel.pendingRequest?.messages.first?.content == "Hello Bell!")

        stub.shouldFail = true
        precondition(viewModel.validateAndStoreRequest("Try again"))
        precondition(viewModel.response == nil && viewModel.responseError == nil)
        await viewModel.submitStoredRequest()
        precondition(viewModel.responseError != nil && !viewModel.isSubmitting)
        precondition(viewModel.response == nil && viewModel.errorMessage == nil)
        precondition(viewModel.pendingRequest?.messages.last?.content == "Try again")

        stub.shouldFail = false
        stub.shouldCancel = true
        precondition(viewModel.validateAndStoreRequest("Cancel this"))
        precondition(viewModel.responseError == nil)
        await viewModel.submitStoredRequest()
        precondition(!viewModel.isSubmitting && viewModel.response == nil)
        precondition(viewModel.responseError?.contains("cancelled") == true)

        let delayed = DelayedService()
        let delayedModel = ChatViewModel(service: delayed, model: "test-model")
        precondition(delayedModel.validateAndStoreRequest("Wait for it"))
        let submission = Task { await delayedModel.submitStoredRequest() }
        while delayed.continuation == nil { await Task.yield() }
        precondition(delayedModel.isSubmitting)
        precondition(delayedModel.response == nil && delayedModel.responseError == nil)
        precondition(!delayedModel.validateAndStoreRequest("Duplicate"))
        delayed.continuation?.resume(returning: ChatResponse(
            model: "test-model", message: ChatMessage(role: "assistant", content: "Delayed reply"), done: true
        ))
        await submission.value
        precondition(!delayedModel.isSubmitting)
        precondition(delayedModel.response?.message.content == "Delayed reply")

        let historyService = StubService()
        let historyModel = ChatViewModel(service: historyService, model: "test-model")
        precondition(historyModel.startNewSession(with: "First question"))
        await historyModel.submitStoredRequest()
        precondition(historyModel.conversation.map(\.kind) == [.user, .assistant])
        precondition(historyModel.validateAndStoreRequest("Follow-up"))
        precondition(historyModel.pendingRequest?.messages.map(\.role) == ["user", "assistant", "user"])
        precondition(historyModel.pendingRequest?.messages.last?.content == "Follow-up")
        await historyModel.submitStoredRequest()
        precondition(historyModel.conversation.count == 4)
        let savedHistory = historyModel.conversation
        precondition(!historyModel.startNewSession(with: "  "))
        precondition(historyModel.conversation == savedHistory)

        historyService.shouldFail = true
        precondition(historyModel.validateAndStoreRequest("Fail this request"))
        await historyModel.submitStoredRequest()
        precondition(historyModel.conversation.last?.kind == .error)
        precondition(historyModel.conversation.count == 6)
        precondition(historyModel.validateAndStoreRequest("Recover"))
        precondition(historyModel.pendingRequest?.messages.count == 6)
        precondition(historyModel.pendingRequest?.messages.allSatisfy { $0.role != "error" } == true)
        precondition(!historyModel.startNewSession(with: "Cannot reset while sending"))
        historyService.shouldFail = false
        await historyModel.submitStoredRequest()
        precondition(historyModel.startNewSession(with: "New session"))
        precondition(historyModel.conversation.count == 1)
        precondition(historyModel.pendingRequest?.messages == [ChatMessage(role: "user", content: "New session")])
        precondition(historyModel.response == nil && historyModel.responseError == nil)
        await historyModel.submitStoredRequest()
        precondition(historyModel.conversation.count == 2)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = HTTPBellAIService(session: session)
        let request = ChatRequest(model: "test-model", messages: [ChatMessage(role: "user", content: "Hello")], stream: false)
        StubURLProtocol.payload = Data(#"{"model":"test-model","choices":[{"message":{"role":"assistant","content":"Hello from mock server"},"finish_reason":"stop"}]}"#.utf8)
        let result = try await service.send(request)
        precondition(result.message.content == "Hello from mock server")
        let sent = StubURLProtocol.capturedRequest!
        precondition(sent.url?.absoluteString == "http://ai-server:11434/v1/chat/completions")
        precondition(sent.httpMethod == "POST")
        precondition(sent.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        var body = sent.httpBody ?? Data()
        if let stream = sent.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let decodedRequest = try JSONDecoder().decode(ChatRequest.self, from: body)
        precondition(decodedRequest == request)

        for code in [401, 403, 429, 500] {
            StubURLProtocol.status = code
            do {
                _ = try await service.send(request)
                preconditionFailure("Expected HTTP failure")
            } catch BellAIServiceError.http(let actual) {
                precondition(actual == code)
            }
        }
        StubURLProtocol.status = 404
        for payload in [
            #"{"error":{"message":"model 'missing' not found","type":"not_found_error"}}"#,
            #"{"error":"model 'missing' not found"}"#
        ] {
            StubURLProtocol.payload = Data(payload.utf8)
            do {
                _ = try await service.send(request)
                preconditionFailure("Expected server error")
            } catch BellAIServiceError.server(let code, let message) {
                precondition(code == 404 && message == "model 'missing' not found")
            }
        }
        StubURLProtocol.status = 200
        for payload in [
            "not JSON",
            #"{"model":"test","choices":[]}"#,
            #"{"model":"test","choices":[{"message":{"role":"assistant","content":"partial"},"finish_reason":null}]}"#,
            #"{"model":"test","choices":[{"message":{"role":"user","content":"wrong role"},"finish_reason":"stop"}]}"#,
            #"{"model":"test","message":{"role":"assistant","content":"old format"},"done":true}"#
        ] {
            StubURLProtocol.payload = Data(payload.utf8)
            do {
                _ = try await service.send(request)
                preconditionFailure("Expected invalid response")
            } catch BellAIServiceError.invalidResponse {}
        }
        print("All Ollama submission checks passed.")
    }
}
