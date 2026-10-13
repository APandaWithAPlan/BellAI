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
    func send(_ request: ChatRequest) async throws -> ChatResponse {
        requests.append(request)
        if shouldFail { throw BellAIServiceError.http(429) }
        return ChatResponse(model: request.model, message: ChatMessage(role: "assistant", content: "Mock reply"), done: true)
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
        precondition(viewModel.pendingRequest?.messages.first?.content == "Hello Bell!")

        stub.shouldFail = true
        precondition(viewModel.validateAndStoreRequest("Try again"))
        await viewModel.submitStoredRequest()
        precondition(viewModel.errorMessage != nil && !viewModel.isSubmitting)
        precondition(viewModel.pendingRequest?.messages.first?.content == "Try again")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = HTTPBellAIService(apiKey: "test-key", session: session)
        let request = ChatRequest(model: "test-model", messages: [ChatMessage(role: "user", content: "Hello")], stream: false)
        StubURLProtocol.payload = Data(#"{"model":"test-model","message":{"role":"assistant","content":"Hello from mock Ollama"},"done":true}"#.utf8)
        let result = try await service.send(request)
        precondition(result.message.content == "Hello from mock Ollama")
        let sent = StubURLProtocol.capturedRequest!
        precondition(sent.url?.absoluteString == "https://ollama.com/api/chat")
        precondition(sent.httpMethod == "POST")
        precondition(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
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
        StubURLProtocol.status = 200
        for payload in ["not JSON", #"{"model":"test","message":{"role":"assistant","content":"partial"},"done":false}"#] {
            StubURLProtocol.payload = Data(payload.utf8)
            do {
                _ = try await service.send(request)
                preconditionFailure("Expected invalid response")
            } catch BellAIServiceError.invalidResponse {}
        }
        StubURLProtocol.capturedRequest = nil
        do {
            _ = try await HTTPBellAIService(apiKey: "", session: session).send(request)
            preconditionFailure("Expected missing key")
        } catch BellAIServiceError.missingKey {}
        precondition(StubURLProtocol.capturedRequest == nil)
        print("All Ollama submission checks passed.")
    }
}
