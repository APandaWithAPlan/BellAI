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

@MainActor
final class StubVoice: VoiceStreamService {
    var events: [VoiceEvent] = []
    var error: Error?
    var requests: [ChatRequest] = []
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<VoiceEvent, Error> {
        requests.append(request)
        let queued = self.events, failure = self.error
        return AsyncThrowingStream { continuation in
            for event in queued { continuation.yield(event) }
            continuation.finish(throwing: failure)
        }
    }
}

@MainActor
final class StubSpeech: SpeechPlaying {
    var isSpeaking = false
    var clips: [Data] = []
    var stopCount = 0
    func enqueue(_ wav: Data) { clips.append(wav) }
    func stop() { stopCount += 1 }
}

@main
struct OllamaSubmissionChecks {
    @MainActor
    static func main() async throws {
        let stub = StubService()
        let viewModel = ChatViewModel(service: stub, model: "test-model")
        await testValidationAndSuccessfulSubmission(stub: stub, viewModel: viewModel)
        await testFailedSubmissionClearsPreviousResponse(stub: stub, viewModel: viewModel)
        await testCancellationClearsPreviousError(stub: stub, viewModel: viewModel)
        await testPendingSubmissionPreventsDuplicates()

        let historyService = StubService()
        let historyModel = ChatViewModel(service: historyService, model: "test-model")
        await testFollowUpHistoryAndInvalidSessionReset(historyModel: historyModel)
        await testHistoryRecoveryAndNewSession(historyService: historyService, historyModel: historyModel)

        await testSpokenReplyStreamsTextAndAudio()
        await testSpeakerOffUsesPlainText()
        await testVoiceServerDownFallsBackToText()
        await testVoiceFailureMidReplyKeepsPartialText()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = HTTPBellAIService(session: session)
        let request = ChatRequest(model: "test-model", messages: [ChatMessage(role: "user", content: "Hello")], stream: false)
        try await testHTTPRequestAndResponse(service: service, request: request)
        try await testHTTPStatusErrors(service: service, request: request)
        try await testServerErrorMessages(service: service, request: request)
        try await testInvalidResponses(service: service, request: request)
        print("All Ollama submission checks passed.")
    }

    @MainActor
    private static func testValidationAndSuccessfulSubmission(stub: StubService, viewModel: ChatViewModel) async {
        precondition(!viewModel.validateAndStoreRequest(" \n "))
        precondition(viewModel.pendingRequest == nil && !viewModel.isSubmitting)
        precondition(!viewModel.validateAndStoreRequest(String(repeating: "a", count: 4_001)))
        precondition(viewModel.validateAndStoreRequest("  Hello BellAI!\n"))
        precondition(viewModel.pendingRequest?.messages.first?.content == "Hello BellAI!")
        precondition(!viewModel.validateAndStoreRequest("duplicate"))
        await viewModel.submitStoredRequest()
        precondition(stub.requests.count == 1 && !viewModel.isSubmitting)
        precondition(viewModel.errorMessage == nil)
        precondition(viewModel.response?.message.content == "Mock reply")
        precondition(viewModel.responseError == nil)
        precondition(viewModel.pendingRequest?.messages.first?.content == "Hello BellAI!")
    }

    @MainActor
    private static func testFailedSubmissionClearsPreviousResponse(stub: StubService, viewModel: ChatViewModel) async {
        stub.shouldFail = true
        precondition(viewModel.validateAndStoreRequest("Try again"))
        precondition(viewModel.response == nil && viewModel.responseError == nil)
        await viewModel.submitStoredRequest()
        precondition(viewModel.responseError != nil && !viewModel.isSubmitting)
        precondition(viewModel.response == nil && viewModel.errorMessage == nil)
        precondition(viewModel.pendingRequest?.messages.last?.content == "Try again")
    }

    @MainActor
    private static func testCancellationClearsPreviousError(stub: StubService, viewModel: ChatViewModel) async {
        stub.shouldFail = false
        stub.shouldCancel = true
        precondition(viewModel.validateAndStoreRequest("Cancel this"))
        precondition(viewModel.responseError == nil)
        await viewModel.submitStoredRequest()
        precondition(!viewModel.isSubmitting && viewModel.response == nil)
        precondition(viewModel.responseError?.contains("cancelled") == true)
    }

    @MainActor
    private static func testPendingSubmissionPreventsDuplicates() async {
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
    }

    @MainActor
    private static func testFollowUpHistoryAndInvalidSessionReset(historyModel: ChatViewModel) async {
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
    }

    @MainActor
    private static func testHistoryRecoveryAndNewSession(historyService: StubService, historyModel: ChatViewModel) async {
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
    }

    @MainActor
    private static func spokenViewModel(
        voice: StubVoice, speech: StubSpeech, text: StubService
    ) -> ChatViewModel {
        ChatViewModel(service: text, voiceService: voice, speech: speech, model: "test-model")
    }

    @MainActor
    private static func testSpokenReplyStreamsTextAndAudio() async {
        let voice = StubVoice(), speech = StubSpeech(), text = StubService()
        voice.events = [
            .text("Hello "),
            .sentence(index: 0, text: "Hello there.", audio: Data([1])),
            .text("there."),
            .sentence(index: 1, text: "Bye.", audio: Data([2])),
            .done
        ]
        let model = spokenViewModel(voice: voice, speech: speech, text: text)
        precondition(model.startNewSession(with: "Hi"))
        await model.submitStoredRequest()
        precondition(voice.requests.count == 1 && text.requests.isEmpty)
        precondition(speech.clips == [Data([1]), Data([2])])
        precondition(model.conversation.map(\.kind) == [.user, .assistant])
        precondition(model.conversation.last?.content == "Hello there.")
        precondition(model.response?.message.content == "Hello there.")
        precondition(!model.isSubmitting && model.responseError == nil)
    }

    @MainActor
    private static func testSpeakerOffUsesPlainText() async {
        let voice = StubVoice(), speech = StubSpeech(), text = StubService()
        let model = spokenViewModel(voice: voice, speech: speech, text: text)
        model.isSpeakerEnabled = false
        precondition(speech.stopCount == 1)
        precondition(model.startNewSession(with: "Hi"))
        await model.submitStoredRequest()
        precondition(voice.requests.isEmpty && text.requests.count == 1)
        precondition(model.conversation.last?.content == "Mock reply")
        model.isSpeakerEnabled = true
        precondition(model.validateAndStoreRequest("Again"))
        voice.events = [.text("Spoken"), .done]
        await model.submitStoredRequest()
        precondition(voice.requests.count == 1 && model.conversation.last?.content == "Spoken")
    }

    @MainActor
    private static func testVoiceServerDownFallsBackToText() async {
        let voice = StubVoice(), speech = StubSpeech(), text = StubService()
        voice.error = BellAIServiceError.invalidResponse
        let model = spokenViewModel(voice: voice, speech: speech, text: text)
        precondition(model.startNewSession(with: "Hi"))
        await model.submitStoredRequest()
        precondition(voice.requests.count == 1 && text.requests.count == 1)
        precondition(model.conversation.map(\.kind) == [.user, .assistant])
        precondition(model.conversation.last?.content == "Mock reply" && model.responseError == nil)
        precondition(speech.clips.isEmpty)
    }

    @MainActor
    private static func testVoiceFailureMidReplyKeepsPartialText() async {
        let voice = StubVoice(), speech = StubSpeech(), text = StubService()
        voice.events = [.text("Part of a reply")]
        voice.error = VoiceStreamError.endedEarly
        let model = spokenViewModel(voice: voice, speech: speech, text: text)
        precondition(model.startNewSession(with: "Hi"))
        await model.submitStoredRequest()
        precondition(text.requests.isEmpty)
        precondition(model.conversation.map(\.kind) == [.user, .assistant, .error])
        precondition(model.conversation[1].content == "Part of a reply")
        precondition(model.responseError != nil && !model.isSubmitting)
    }

    @MainActor
    private static func testHTTPRequestAndResponse(service: HTTPBellAIService, request: ChatRequest) async throws {
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
    }

    @MainActor
    private static func testHTTPStatusErrors(service: HTTPBellAIService, request: ChatRequest) async throws {
        for code in [401, 403, 429, 500] {
            StubURLProtocol.status = code
            do {
                _ = try await service.send(request)
                preconditionFailure("Expected HTTP failure")
            } catch BellAIServiceError.http(let actual) {
                precondition(actual == code)
            }
        }
    }

    @MainActor
    private static func testServerErrorMessages(service: HTTPBellAIService, request: ChatRequest) async throws {
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
    }

    @MainActor
    private static func testInvalidResponses(service: HTTPBellAIService, request: ChatRequest) async throws {
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
    }
}
