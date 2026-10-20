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

@MainActor
final class StubFood: FoodAnalysisService {
    var summary = "About 600 calories."
    var wav = Data([1, 2, 3])
    var analyzeError: Error?
    var speakError: Error?
    var analyzed: [(jpeg: Data?, note: String?)] = []
    func analyze(jpeg: Data?, note: String?) async throws -> String {
        analyzed.append((jpeg, note))
        if let analyzeError { throw analyzeError }
        return summary
    }
    func speak(_ text: String) async throws -> Data {
        if let speakError { throw speakError }
        return wav
    }
}

@MainActor
final class StubStore: UserDataStore {
    var stored: [String: Any]?
    var saves: [[String: Any]] = []
    var loadError: Error?
    var saveError: Error?
    func load() async throws -> [String: Any]? {
        if let loadError { throw loadError }
        return stored
    }
    func save(_ data: [String: Any]) async throws {
        if let saveError { throw saveError }
        saves.append(data)
        stored = data
    }
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

        await testPhotoSummaryIsShownAndSpoken()
        await testPhotoFailuresAndSpeakerOff()

        await testTasksLoadAddToggleDelete()
        await testTasksKeepOtherStoredData()
        await testTasksFailures()
        await testBellKnowsOpenTasks()

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
        try await testFoodAnalysisHTTP(session: session)
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
    private static func testTasksLoadAddToggleDelete() async {
        let store = StubStore()
        let model = TasksViewModel(store: store)
        precondition(!model.add("too early")) // not loaded yet, a save would overwrite
        await model.load()
        precondition(model.isLoaded && model.tasks.isEmpty)
        precondition(!model.add("   "))
        precondition(model.add("  Buy milk  "))
        precondition(model.add("Call mom"))
        await model.waitForSaves()
        precondition(model.tasks.map(\.title) == ["Buy milk", "Call mom"])
        precondition(store.saves.count == 2)

        model.toggle(model.tasks[0])
        model.delete(at: IndexSet(integer: 1))
        await model.waitForSaves()

        // a fresh model reads back what was saved
        let reloaded = TasksViewModel(store: store)
        await reloaded.load()
        precondition(reloaded.tasks.count == 1)
        precondition(reloaded.tasks[0].title == "Buy milk" && reloaded.tasks[0].isDone)
        precondition(reloaded.tasks[0].id == model.tasks[0].id)
    }

    @MainActor
    private static func testTasksKeepOtherStoredData() async {
        let store = StubStore()
        store.stored = ["name": "Maya"]
        let model = TasksViewModel(store: store)
        await model.load()
        model.add("Water plants")
        await model.waitForSaves()
        precondition(store.stored?["name"] as? String == "Maya")
        precondition(store.stored?["tasks"] != nil)
    }

    @MainActor
    private static func testTasksFailures() async {
        let store = StubStore()
        store.loadError = BellAIServiceError.invalidResponse
        let model = TasksViewModel(store: store)
        await model.load()
        precondition(!model.isLoaded && model.errorMessage != nil)
        precondition(!model.add("nope"))

        // retry works once the store is back
        store.loadError = nil
        model.errorMessage = nil
        await model.load()
        precondition(model.isLoaded && model.errorMessage == nil)

        store.saveError = BellAIServiceError.http(500)
        precondition(model.add("Still shows up locally"))
        await model.waitForSaves()
        precondition(model.tasks.count == 1 && model.errorMessage != nil)
    }

    @MainActor
    private static func testBellKnowsOpenTasks() async {
        let store = StubStore()
        let tasks = TasksViewModel(store: store)
        precondition(tasks.openTaskSummary == nil) // not loaded, say nothing
        await tasks.load()
        precondition(tasks.openTaskSummary == "I have no open tasks")
        tasks.add("Buy milk")
        tasks.add("Call mom")
        tasks.toggle(tasks.tasks[1])
        await tasks.waitForSaves()
        precondition(tasks.openTaskSummary == "my open tasks are: Buy milk")

        let chat = ChatViewModel(service: StubService(), model: "test-model")
        chat.contextProvider = { tasks.openTaskSummary }
        precondition(chat.startNewSession(with: "What should I do?"))
        let sent = chat.pendingRequest?.messages.last?.content ?? ""
        precondition(sent.contains("my open tasks are: Buy milk"))
        precondition(sent.hasSuffix("What should I do?"))
        precondition(chat.conversation.last?.content == "What should I do?") // chat shows only what was typed

        // no context, request goes out untouched
        let plain = ChatViewModel(service: StubService(), model: "test-model")
        precondition(plain.startNewSession(with: "Hi"))
        precondition(plain.pendingRequest?.messages.last?.content == "Hi")
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

    @MainActor
    private static func testPhotoSummaryIsShownAndSpoken() async {
        let food = StubFood(), speech = StubSpeech()
        let model = ChatViewModel(foodService: food, speech: speech, model: "test-model")
        precondition(model.validateAndStorePhoto(Data([9]), note: " no sauce ", startsNewSession: true))
        precondition(model.isSubmitting)
        precondition(!model.validateAndStorePhoto(Data([9]))) // one at a time
        await model.submitStoredPhoto()
        precondition(!model.isSubmitting)
        precondition(food.analyzed.count == 1 && food.analyzed[0].jpeg == Data([9]) && food.analyzed[0].note == "no sauce")
        precondition(model.conversation.map(\.kind) == [.user, .assistant])
        precondition(model.conversation[0].content == "📷 no sauce")
        precondition(model.conversation[1].content == "About 600 calories.")
        precondition(speech.clips == [Data([1, 2, 3])])

        // no note sends none
        precondition(model.validateAndStorePhoto(Data([8])))
        await model.submitStoredPhoto()
        precondition(food.analyzed[1].note == nil && model.conversation[2].content == "📷 Photo")

        // needs the food service
        precondition(!ChatViewModel(model: "test-model").validateAndStorePhoto(Data([9])))
    }

    @MainActor
    private static func testPhotoFailuresAndSpeakerOff() async {
        let food = StubFood(), speech = StubSpeech()
        let model = ChatViewModel(foodService: food, speech: speech, model: "test-model")
        food.analyzeError = BellAIServiceError.server(503, "Ollama is down")
        precondition(model.validateAndStorePhoto(Data([9])))
        await model.submitStoredPhoto()
        precondition(model.conversation.map(\.kind) == [.user, .error])
        precondition(model.responseError?.contains("Ollama is down") == true && !model.isSubmitting)

        // audio failing keeps the text
        food.analyzeError = nil
        food.speakError = BellAIServiceError.http(502)
        precondition(model.validateAndStorePhoto(Data([9])))
        await model.submitStoredPhoto()
        precondition(model.conversation.last?.kind == .assistant && speech.clips.isEmpty)

        food.speakError = nil
        model.isSpeakerEnabled = false
        precondition(model.validateAndStorePhoto(Data([9])))
        await model.submitStoredPhoto()
        precondition(model.conversation.last?.kind == .assistant && speech.clips.isEmpty)
    }

    @MainActor
    private static func testFoodAnalysisHTTP(session: URLSession) async throws {
        let service = HTTPFoodAnalysisService(baseURL: URL(string: "http://ai-server:8000")!, session: session)
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"{"summary":"Roughly 500 calories.","items":[],"totals":{}}"#.utf8)
        let summary = try await service.analyze(jpeg: Data([1]), note: "lunch")
        precondition(summary == "Roughly 500 calories.")
        let sent = StubURLProtocol.capturedRequest!
        precondition(sent.url?.absoluteString == "http://ai-server:8000/analyze" && sent.httpMethod == "POST")
        precondition(sent.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)

        StubURLProtocol.payload = Data([0x52, 0x49, 0x46, 0x46])
        let wav = try await service.speak("Hi")
        precondition(wav == Data([0x52, 0x49, 0x46, 0x46]))
        precondition(StubURLProtocol.capturedRequest?.url?.absoluteString == "http://ai-server:8000/speak")
        precondition(StubURLProtocol.capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")

        StubURLProtocol.status = 400
        StubURLProtocol.payload = Data(#"{"detail":"Nothing to say."}"#.utf8)
        do {
            _ = try await service.speak("")
            preconditionFailure("Expected 400")
        } catch BellAIServiceError.server(400, let message) {
            precondition(message == "Nothing to say.")
        }
        StubURLProtocol.status = 413
        StubURLProtocol.payload = Data(#"{"detail":"too big"}"#.utf8)
        do {
            _ = try await service.analyze(jpeg: Data([1]), note: nil)
            preconditionFailure("Expected 413")
        } catch BellAIServiceError.server(413, let message) {
            precondition(message.contains("too large"))
        }
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"{"nope":1}"#.utf8)
        do {
            _ = try await service.analyze(jpeg: nil, note: "x")
            preconditionFailure("Expected invalid response")
        } catch BellAIServiceError.invalidResponse {}
    }
}
