// Standalone checks: run with scripts/check-ollama.sh. No real API calls or keys.
import AVFoundation
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
final class StubLogger: MealLogging {
    var logged: [(nutrition: Nutrition, name: String)] = []
    var error: Error?
    func log(_ nutrition: Nutrition, name: String) async throws {
        if let error { throw error }
        logged.append((nutrition, name))
    }
}

@MainActor
final class StubFood: FoodAnalysisService {
    var summary = "About 600 calories."
    var nutrition: Nutrition? = nil
    var wav = Data([1, 2, 3])
    var analyzeError: Error?
    var speakError: Error?
    var analyzed: [(jpeg: Data?, note: String?)] = []
    func analyze(jpeg: Data?, note: String?) async throws -> MealAnalysis {
        analyzed.append((jpeg, note))
        if let analyzeError { throw analyzeError }
        return MealAnalysis(summary: summary, nutrition: nutrition)
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

@MainActor
final class StubMicrophone: MicrophoneListening {
    var continuation: CheckedContinuation<String?, Error>?
    var transcribing: (@MainActor () -> Void)?
    var finishes = 0
    func listen(onReady: @escaping @MainActor () -> Void, onTranscribing: @escaping @MainActor () -> Void) async throws -> String? {
        onReady()
        transcribing = onTranscribing
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete(_ text: String?) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: text)
    }
    // the real one goes on to transcribe, so the checks decide when
    func finish() { finishes += 1 }
    func cancel() {
        let pending = continuation
        continuation = nil
        pending?.resume(throwing: CancellationError())
    }
}

@MainActor
final class StubMail: MailService {
    var items: [MailItem] = []
    var pending: [MailDraft] = []
    var error: Error?
    var sendError: Error?
    var written: [(saying: String, to: String?, replyTo: Int?)] = []
    var sent: [Int] = []
    var discarded: [Int] = []
    func recent(limit: Int) async throws -> [MailItem] {
        if let error { throw error }
        return items
    }
    func pendingDrafts() async throws -> [MailDraft] {
        if let error { throw error }
        return pending
    }
    func writeDraft(saying: String, to: String?, replyTo: Int?) async throws -> MailDraft {
        written.append((saying, to, replyTo))
        if let error { throw error }
        let draft = MailDraft(id: 40 + written.count, to: to ?? "ana@example.com", subject: "Re: Lunch", body: "Yes, Thursday works.", replyTo: replyTo)
        pending.insert(draft, at: 0)
        return draft
    }
    func send(_ draft: MailDraft) async throws {
        pending.removeAll { $0.id == draft.id } // the server closes a draft either way
        if let sendError { throw sendError }
        sent.append(draft.id)
    }
    func discard(_ draft: MailDraft) async throws {
        pending.removeAll { $0.id == draft.id }
        discarded.append(draft.id)
    }
}

@MainActor
final class StubInsights: InsightsService {
    var result = Insights(status: "low_protein", summary: "You're low on protein today.",
                          foods: [Insights.Food(title: "Greek yogurt", why: "Easy protein.", kcal: 180, proteinG: 17)],
                          workouts: [Insights.Workout(title: "Brisk walk", why: "Easy on the joints.", minutes: 20, intensity: "light")])
    var error: Error?
    var asked: [(preferences: FoodPreferences, meals: [LoggedMeal])] = []
    var gate: CheckedContinuation<Void, Never>? // holds the answer back until the check lets it go
    var holds = false
    func insights(for preferences: FoodPreferences, meals: [LoggedMeal]) async throws -> Insights {
        asked.append((preferences, meals))
        if holds { await withCheckedContinuation { gate = $0 } }
        if let error { throw error }
        return result
    }
    func release() {
        let waiting = gate
        gate = nil
        waiting?.resume()
    }
}

@main
struct OllamaSubmissionChecks {
    @MainActor
    static func main() async throws {
        testSpeechEndpoint()
        testAudioCapture()
        testMailAddresses()
        testFoodPreferences()
        await testMealJournalAndPhotoLogging()
        await testInsightsViewModel()
        await testListeningThenTranscribing()
        await testMicrophoneSubmissionAndCancellation()
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

        await testMealPhotoResultStaysOutOfTheChat()
        await testEditingMealLogsIt()
        await testLoggingAsIsAndFailures()
        await testMealPhotoFailuresAndDismissing()

        testServerSettings()
        await testTasksLoadAddToggleDelete()
        await testTasksReloadAfterServerChange()
        await testTasksKeepOtherStoredData()
        await testTasksFailures()
        await testBellKnowsOpenTasks()
        await testMailViewModel()

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
        try await testTranscriptionHTTP(session: session)
        try await testMailHTTP(session: session)
        try await testInsightsHTTP(session: session)
        await testServerConnectionHealth(session: session)
        print("All Ollama submission checks passed.")
    }

    // the microphone: a tap while listening sends what was said, and a tap while transcribing cancels
    @MainActor
    private static func testListeningThenTranscribing() async {
        let microphone = StubMicrophone()
        let api = StubService()
        let model = ChatViewModel(service: api, microphone: microphone, model: "test")
        model.toggleMicrophone()
        while microphone.continuation == nil { await Task.yield() }
        precondition(model.isListening && !model.isTranscribing)
        model.toggleMicrophone() // finishes, it doesn't throw the recording away
        precondition(microphone.finishes == 1 && model.isListening && microphone.continuation != nil)
        microphone.transcribing?()
        precondition(!model.isListening && model.isTranscribing)
        microphone.complete("Turn on the lights")
        while model.isTranscribing || model.isSubmitting { await Task.yield() }
        precondition(model.conversation.map(\.content) == ["Turn on the lights", "Mock reply"])
        precondition(model.errorMessage == nil && !model.isListening)

        model.toggleMicrophone()
        while microphone.continuation == nil { await Task.yield() }
        microphone.transcribing?()
        precondition(model.isTranscribing)
        model.toggleMicrophone() // a tap while transcribing gives up on it
        await Task.yield()
        precondition(!model.isTranscribing && !model.isListening && microphone.continuation == nil)
        precondition(api.requests.count == 1 && model.errorMessage == nil)
    }

    private static func testSpeechEndpoint() {
        // a pause after talking ends it
        var talking = SpeechEndpoint()
        for _ in 0..<20 { precondition(!talking.hear(level: 0.1, seconds: 0.1)) }
        precondition(talking.heardSpeech)
        var quietSteps = 0
        while !talking.hear(level: 0.005, seconds: 0.1) { quietSteps += 1 }
        precondition((13...14).contains(quietSteps), "\(quietSteps)")
        // a short pause in the middle of a sentence doesn't
        var sentence = SpeechEndpoint()
        _ = sentence.hear(level: 0.1, seconds: 0.1)
        for _ in 0..<10 { precondition(!sentence.hear(level: 0, seconds: 0.1)) }
        precondition(!sentence.hear(level: 0.1, seconds: 0.1))
        for _ in 0..<10 { precondition(!sentence.hear(level: 0, seconds: 0.1)) }
        // nobody talking gives up after about 8 seconds, and never claims to have heard anyone
        var silent = SpeechEndpoint()
        var silentSteps = 0
        while !silent.hear(level: 0, seconds: 0.1) { silentSteps += 1 }
        precondition((78...80).contains(silentSteps) && !silent.heardSpeech, "\(silentSteps)")
        // and it never runs past a minute
        var endless = SpeechEndpoint()
        var endlessSteps = 0
        while !endless.hear(level: 0.1, seconds: 0.1) { endlessSteps += 1 }
        precondition((598...600).contains(endlessSteps), "\(endlessSteps)")
    }

    private static func testAudioCapture() {
        let input = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let capture = AudioCapture(input: input)!
        // half a second of a tone, which comes out as 16 kHz mono 16 bit, a third as many samples
        let buffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 24_000)!
        buffer.frameLength = 24_000
        for index in 0..<24_000 {
            buffer.floatChannelData![0][index] = 0.5 * sin(2 * .pi * 440 * Float(index) / 48_000)
        }
        capture.append(buffer)
        let wav = capture.wav
        let samples = (wav.count - 44) / 2
        precondition((7_700...8_100).contains(samples), "\(samples)")
        precondition(String(decoding: wav[0..<4], as: UTF8.self) == "RIFF" && String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ")
        precondition(String(decoding: wav[36..<40], as: UTF8.self) == "data")
        func le(_ range: Range<Int>) -> Int { wav[range].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) } }
        precondition(le(4..<8) == wav.count - 8 && le(22..<24) == 1 && le(24..<28) == 16_000 && le(34..<36) == 16 && le(40..<44) == samples * 2)
        let level = capture.takeLoudness()
        precondition((0.30...0.40).contains(level), "\(level)") // a 0.5 sine is about 0.35 RMS
        precondition(capture.takeLoudness() == 0) // asking resets it
        // a two channel microphone is mixed down to one
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let both = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 4_410)!
        both.frameLength = 4_410
        for index in 0..<4_410 {
            both.floatChannelData![0][index] = 0.5 * sin(2 * .pi * 440 * Float(index) / 44_100)
            both.floatChannelData![1][index] = 0.5 * sin(2 * .pi * 440 * Float(index) / 44_100)
        }
        let stereoCapture = AudioCapture(input: stereo)!
        stereoCapture.append(both)
        let stereoSamples = (stereoCapture.wav.count - 44) / 2
        precondition((1_400...1_650).contains(stereoSamples) && stereoCapture.takeLoudness() > 0.25, "\(stereoSamples)")
        // nothing recorded is still a valid, empty wav
        precondition(AudioCapture(input: input)!.wav.count == 44)
    }

    private static func testMailAddresses() {
        precondition(MailAddress.name("Ana Lopez <ana@example.com>") == "Ana Lopez")
        precondition(MailAddress.name("\"Lopez, Ana\" <ana@example.com>") == "Lopez, Ana")
        precondition(MailAddress.name("<ana@example.com>") == "ana@example.com")
        precondition(MailAddress.name("ana@example.com") == "ana@example.com")
        precondition(MailAddress.name("  ") == "")
        precondition(MailAddress.looksValid("ana@example.com") && MailAddress.looksValid(" ana@example.com "))
        for bad in ["", "ana", "ana@", "@example.com", "ana@example", "ana@.com", "ana@example.", "a b@example.com", "a@b@example.com"] {
            precondition(!MailAddress.looksValid(bad), bad)
        }
    }

    @MainActor
    private static func testTranscriptionHTTP(session: URLSession) async throws {
        let service = HTTPSpeechTranscriber(baseURL: URL(string: "http://ai-server:8000")!, session: session)
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"{"text":"  Remind me to call the dentist.  "}"#.utf8)
        let wav = Data("RIFFxxxx".utf8)
        let text = try await service.transcribe(wav)
        precondition(text == "Remind me to call the dentist.")
        let sent = StubURLProtocol.capturedRequest!
        precondition(sent.url?.absoluteString == "http://ai-server:8000/transcribe" && sent.httpMethod == "POST")
        precondition(sent.value(forHTTPHeaderField: "Content-Type") == "audio/wav")
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
        precondition(body == wav)

        StubURLProtocol.payload = Data(#"{"text":""}"#.utf8) // silence
        let silence = try await service.transcribe(wav)
        precondition(silence == "")
        StubURLProtocol.status = 400
        StubURLProtocol.payload = Data(#"{"detail":"Send a wav recording."}"#.utf8)
        do {
            _ = try await service.transcribe(wav)
            preconditionFailure("Expected 400")
        } catch BellAIServiceError.server(400, let message) {
            precondition(message == "Send a wav recording.")
        }
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"{"nope":1}"#.utf8)
        do {
            _ = try await service.transcribe(wav)
            preconditionFailure("Expected invalid response")
        } catch BellAIServiceError.invalidResponse {}
    }

    @MainActor
    private static func testMailHTTP(session: URLSession) async throws {
        let service = HTTPMailService(baseURL: URL(string: "http://ai-server:8000")!, session: session)
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"""
        {"mail":[{"id":10,"account":"me@example.com","received":"2026-11-03T05:09:44+00:00","sender":"Google <no-reply@accounts.google.com>",
        "subject":"Security alert","importance":"high","summary":"A new app password was created.","action":"Check your account.","due":""},
        {"id":9,"account":"me@example.com","received":"not a date","sender":"a@b.co","subject":"Hi","importance":"urgent","summary":"","action":"","due":""}]}
        """#.utf8)
        let mail = try await service.recent(limit: 50)
        precondition(StubURLProtocol.capturedRequest?.url?.absoluteString == "http://ai-server:8000/mail?limit=50")
        precondition(mail.count == 2 && mail[0].id == 10 && mail[0].importance == .high && mail[0].senderName == "Google")
        precondition(mail[0].received == Date(timeIntervalSince1970: 1_793_682_584), "\(String(describing: mail[0].received))")
        precondition(mail[1].importance == .normal && mail[1].received == nil) // what it doesn't know is left out, not a failure

        StubURLProtocol.payload = Data(#"{"drafts":[{"id":7,"account":"me@example.com","to":"sam@example.com","subject":"Re: Lunch","body":"Thursday works.","reply_to":3,"status":"pending","created":"x"}]}"#.utf8)
        let drafts = try await service.pendingDrafts()
        precondition(StubURLProtocol.capturedRequest?.url?.absoluteString == "http://ai-server:8000/drafts?status=pending")
        precondition(drafts == [MailDraft(id: 7, account: "me@example.com", to: "sam@example.com", subject: "Re: Lunch", body: "Thursday works.", replyTo: 3)])

        StubURLProtocol.payload = Data(#"{"id":8,"account":"me@example.com","to":"sam@example.com","subject":"Dinner","body":"Is Saturday on?","reply_to":null,"status":"pending","created":"x"}"#.utf8)
        let draft = try await service.writeDraft(saying: "ask if dinner is on", to: "sam@example.com", replyTo: nil)
        let sent = StubURLProtocol.capturedRequest!
        precondition(sent.url?.absoluteString == "http://ai-server:8000/drafts" && sent.httpMethod == "POST")
        precondition(draft.id == 8 && draft.replyTo == nil)
        var body = Data()
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
        let fields = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        precondition(fields["instruction"] as? String == "ask if dinner is on" && fields["to"] as? String == "sam@example.com" && fields["reply_to"] == nil)

        StubURLProtocol.payload = Data(#"{"ok":true}"#.utf8)
        try await service.send(draft)
        precondition(StubURLProtocol.capturedRequest?.url?.absoluteString == "http://ai-server:8000/drafts/8/send" && StubURLProtocol.capturedRequest?.httpMethod == "POST")
        try await service.discard(draft)
        precondition(StubURLProtocol.capturedRequest?.url?.absoluteString == "http://ai-server:8000/drafts/8/discard")

        // the server words its errors for people, so they are shown as they are
        StubURLProtocol.status = 409
        StubURLProtocol.payload = Data(#"{"detail":"That draft was already sent or discarded."}"#.utf8)
        do {
            try await service.send(draft)
            preconditionFailure("Expected 409")
        } catch let error as MailServiceError {
            precondition(error.localizedDescription == "That draft was already sent or discarded.")
        }
        StubURLProtocol.status = 422
        StubURLProtocol.payload = Data(#"{"detail":[{"msg":"too short"}]}"#.utf8)
        do {
            _ = try await service.writeDraft(saying: "", to: nil, replyTo: 1)
            preconditionFailure("Expected 422")
        } catch let error as MailServiceError {
            precondition(error.localizedDescription.contains("HTTP 422"))
        }
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"{"nope":1}"#.utf8)
        do {
            _ = try await service.recent(limit: 5)
            preconditionFailure("Expected invalid response")
        } catch MailServiceError.invalidResponse {}
    }

    @MainActor
    private static func testMailViewModel() async {
        let service = StubMail()
        service.items = [
            MailItem(id: 2, sender: "Bank <alerts@bank.example>", subject: "Statement", importance: .high, summary: "Your statement is ready.", action: "Review it."),
            MailItem(id: 1, sender: "Friend <sam@example.com>", subject: "Lunch?", importance: .normal, summary: "Asks about Thursday."),
        ]
        let model = MailViewModel(service: service)
        precondition(model.cardDetail == "Loading…" && model.importantSummary == nil) // never "no mail" before we know
        await model.refresh()
        precondition(model.isLoaded && model.mail.count == 2 && model.cardDetail == "1 important")
        precondition(model.importantSummary == "my important emails are: Bank: Your statement is ready.")

        // a draft waiting for approval comes first on the card
        service.pending = [MailDraft(id: 5, to: "sam@example.com", subject: "Re: Lunch?", body: "Yes.", replyTo: 1)]
        await model.refresh()
        precondition(model.drafts.count == 1 && model.cardDetail == "1 to approve")

        // a failed refresh keeps what is shown and says so
        service.error = MailServiceError.message("The mail server isn't running.")
        await model.refresh()
        precondition(model.mail.count == 2 && model.loadError == "The mail server isn't running." && model.cardDetail == "Offline")
        service.error = nil
        await model.refresh()
        precondition(model.loadError == nil)

        // a reply: written, shown for approval, nothing sent
        let reply = await model.writeReply(to: service.items[1], saying: "  yes, Thursday works  ")
        precondition(reply?.replyTo == 1 && service.written.last?.saying == "yes, Thursday works" && service.written.last?.to == nil)
        precondition(model.drafts.first?.id == reply?.id && service.sent.isEmpty)
        let blank = await model.writeReply(to: service.items[1], saying: "  ")
        precondition(blank == nil && model.actionError != nil && service.written.count == 1)
        let typo = await model.writeNew(to: "not an address", saying: "hi")
        precondition(typo == nil && service.written.count == 1)
        let fresh = await model.writeNew(to: " sam@example.com ", saying: "ask about dinner")
        precondition(fresh != nil && service.written.last?.to == "sam@example.com" && service.written.last?.replyTo == nil && model.actionError == nil)
        service.error = MailServiceError.message("I couldn't reach the chat model to write it.")
        let failed = await model.writeNew(to: "sam@example.com", saying: "hi")
        precondition(failed == nil)
        precondition(model.actionError == "I couldn't reach the chat model to write it." && !model.isWorking)
        service.error = nil

        // sending only happens when asked, and takes it off the list
        let sendCount = model.drafts.count
        let wasSent = await model.send(reply!)
        precondition(wasSent && service.sent == [reply!.id] && model.drafts.count == sendCount - 1)
        let wasDiscarded = await model.discard(fresh!)
        precondition(wasDiscarded && service.discarded == [fresh!.id])
        // a send that fails is gone from the list too, because the server won't send it a second time
        service.pending = [MailDraft(id: 99, to: "sam@example.com", subject: "x", body: "y")]
        await model.refresh()
        service.sendError = MailServiceError.message("It didn't send (login failed).")
        let notSent = await model.send(model.drafts[0])
        precondition(!notSent)
        precondition(model.actionError == "It didn't send (login failed)." && !model.drafts.contains { $0.id == 99 })
        service.sendError = nil

        // a changed server is a different mailbox
        service.items = []
        service.pending = []
        await model.reload()
        precondition(model.mail.isEmpty && model.cardDetail == "No mail" && model.importantSummary == "I have no important emails")
    }

    private static func requestBody(_ request: URLRequest) -> Data {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        return body
    }

    @MainActor
    private static func freshDefaults() -> UserDefaults {
        let name = "bellai-check-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor
    private static func testFoodPreferences() {
        precondition(FoodPreferences.list(from: " Peanuts, shellfish ;PEANUTS\n  , Soy ", limit: 20) == ["peanuts", "shellfish", "soy"])
        precondition(FoodPreferences.list(from: "a, b, c, d", limit: 2) == ["a", "b"])
        precondition(FoodPreferences.list(from: " , ;", limit: 5).isEmpty)
        precondition(FoodPreferences.list(from: String(repeating: "x", count: 100), limit: 5) == [String(repeating: "x", count: 40)])

        var preferences = FoodPreferences()
        precondition(preferences.problem == nil && preferences.requestFields.isEmpty) // nothing set leaves it to the server's defaults
        for bad in [{ preferences.calorieGoal = 700 }, { preferences.calorieGoal = 6_500 }, { preferences.proteinGoalGrams = 5 },
                    { preferences.sodiumLimitMg = 20_000 }, { preferences.allergies = Array(repeating: "x", count: 21) }] as [() -> Void] {
            preferences = FoodPreferences()
            bad()
            precondition(preferences.problem != nil)
        }
        preferences = FoodPreferences(calorieGoal: 1_800, proteinGoalGrams: 120, sodiumLimitMg: 2_000, diet: "vegan", goal: "lose",
                                      fitnessLevel: "beginner", allergies: ["peanut"], injuries: ["knee"], dislikes: ["olives"])
        precondition(preferences.problem == nil)
        let fields = preferences.requestFields
        precondition(fields["calorie_goal"] as? Int == 1_800 && fields["protein_goal_g"] as? Int == 120 && fields["sodium_limit_mg"] as? Int == 2_000)
        precondition(fields["diet"] as? String == "vegan" && fields["goal"] as? String == "lose" && fields["fitness_level"] as? String == "beginner")
        precondition(fields["allergies"] as? [String] == ["peanut"] && fields["injuries"] as? [String] == ["knee"] && fields["dislikes"] as? [String] == ["olives"])

        let defaults = freshDefaults()
        precondition(FoodPreferencesStore.load(defaults: defaults) == FoodPreferences())
        FoodPreferencesStore.save(preferences, defaults: defaults)
        precondition(FoodPreferencesStore.load(defaults: defaults) == preferences)
    }

    // what is logged is kept for the recommendations, once, and only after Health has it
    @MainActor
    private static func testMealJournalAndPhotoLogging() async {
        let defaults = freshDefaults()
        let journal = MealJournal(defaults: defaults)
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: noon)!
        let old = Calendar.current.date(byAdding: .day, value: -20, to: noon)!
        journal.add(name: "Old", nutrients: MealNutrients(kcal: 1), now: old)
        journal.add(name: "Yesterday", nutrients: MealNutrients(kcal: 2), now: yesterday)
        journal.add(name: "Lunch", nutrients: MealNutrients(kcal: 600, proteinG: 30, sodiumMg: 900), now: noon)
        journal.add(name: "Breakfast", nutrients: MealNutrients(kcal: 300), now: noon.addingTimeInterval(-3_600))
        precondition(journal.meals.map(\.name) == ["Yesterday", "Lunch", "Breakfast"]) // the old one is gone
        precondition(journal.today(now: noon).map(\.name) == ["Breakfast", "Lunch"]) // today only, oldest first
        precondition(MealJournal(defaults: defaults).meals == journal.meals) // and it is still there next launch
        for index in 0..<250 { journal.add(name: "Meal \(index)", nutrients: MealNutrients(kcal: 1), now: noon) }
        precondition(journal.meals.count == 200)

        // the nutrients keep everything the food model found, with the calories and protein the person settled on
        let found = MealNutrients(kcal: 364, proteinG: 19, carbsG: 25, fatG: 20, fiberG: 3, sugarG: 6, sodiumMg: 700)
        var result = MealResult(MealAnalysis(summary: "About 364 calories, 19 g protein.", nutrition: Nutrition(calories: 364, proteinGrams: 19), nutrients: found))
        precondition(result.loggedNutrients == found)
        precondition(result.correct(to: Nutrition(calories: 500, proteinGrams: 30)))
        precondition(result.loggedNutrients == MealNutrients(kcal: 500, proteinG: 30, carbsG: 25, fatG: 20, fiberG: 3, sugarG: 6, sodiumMg: 700))
        precondition(MealResult(MealAnalysis(summary: "Nothing found.", nutrition: nil)).loggedNutrients == nil)

        let food = StubFood(), logger = StubLogger(), mealJournal = MealJournal(defaults: freshDefaults())
        food.summary = "About 364 calories, 19 g protein."
        food.nutrition = Nutrition(calories: 364, proteinGrams: 19)
        let model = MealPhotoViewModel(foodService: food, logger: logger, journal: mealJournal)
        precondition(model.begin(Data([1]), note: "eggs and toast"))
        await model.analyzeStored()
        // food without the other nutrients found still has calories and protein
        logger.error = MealLoggingError.notAllowed
        await model.log()
        precondition(mealJournal.meals.isEmpty) // Health refused it, so it isn't counted
        logger.error = nil
        await model.log()
        precondition(mealJournal.meals.count == 1 && mealJournal.meals[0].name == "eggs and toast" && mealJournal.meals[0].nutrients.kcal == 364)
        await model.log() // already logged, can't be counted twice
        precondition(mealJournal.meals.count == 1)
    }

    @MainActor
    private static func testInsightsViewModel() async {
        let service = StubInsights()
        let defaults = freshDefaults()
        let journal = MealJournal(defaults: defaults)
        let model = InsightsViewModel(service: service, journal: journal, defaults: defaults)
        precondition(model.phase == .idle && model.mealCount == 0 && model.preferences == FoodPreferences())
        await model.refresh() // no meals is fine, the server encourages logging
        precondition(model.phase == .loaded(service.result) && service.asked.last?.meals.isEmpty == true)

        journal.add(name: "Lunch", nutrients: MealNutrients(kcal: 600, proteinG: 30))
        precondition(model.mealCount == 1)
        await model.refresh()
        precondition(service.asked.last?.meals.map(\.name) == ["Lunch"])

        // a day to try it with is sent in place of the journal and doesn't touch it
        await model.refresh(sample: [LoggedMeal(date: .now, name: "Sample", nutrients: MealNutrients(kcal: 1_000))])
        precondition(service.asked.last?.meals.map(\.name) == ["Sample"] && journal.meals.count == 1)

        service.error = BellAIServiceError.server(503, "The insights server isn't running.")
        await model.refresh()
        precondition(model.phase == .failed(BellAIServiceError.server(503, "The insights server isn't running.").localizedDescription))
        service.error = nil

        // preferences that can't be used are refused and change nothing, good ones are kept for next launch
        var bad = FoodPreferences()
        bad.calorieGoal = 100
        precondition(model.save(bad) != nil && model.preferences == FoodPreferences())
        let good = FoodPreferences(calorieGoal: 1_800, allergies: ["peanut"])
        await model.refresh()
        precondition(model.save(good) == nil && model.preferences == good && model.phase == .idle) // what was shown no longer fits
        precondition(InsightsViewModel(service: service, journal: journal, defaults: defaults).preferences == good)
        await model.refresh()
        precondition(service.asked.last?.preferences == good)

        // an answer that arrives after the preferences changed is not shown
        service.holds = true
        let pending = Task { await model.refresh() }
        while service.gate == nil { await Task.yield() }
        precondition(model.phase == .loading)
        precondition(model.save(FoodPreferences(calorieGoal: 2_400)) == nil && model.phase == .idle)
        service.release()
        await pending.value
        precondition(model.phase == .idle)
        service.holds = false
    }

    @MainActor
    private static func testInsightsHTTP(session: URLSession) async throws {
        let service = HTTPInsightsService(baseURL: URL(string: "http://ai-server:8000")!, session: session)
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"""
        {"type":"insights","status":"low_protein","summary":"You're low on protein today (22 g, target 52 g). Add a protein-rich snack.",
        "flags":[],"totals":{},"targets":{},"calories_remaining":900,
        "food_recommendations":[{"title":"Greek yogurt","why":"Easy protein.","ingredients":["yogurt"],"kcal":180,"protein_g":17,"source":"default"},{"title":"Apple"}],
        "workout_recommendations":[{"title":"Brisk walk","why":"Gentle.","minutes":20,"intensity":"light"}],
        "removed_by_limits":["Peanut butter toast"],"source":"model","model":"m","error":null,"timing_ms":5}
        """#.utf8)
        let meals = [LoggedMeal(date: .now, name: "Toast", nutrients: MealNutrients(kcal: 420, proteinG: 8, carbsG: 80, fatG: 6, fiberG: 4, sugarG: 25, sodiumMg: 450))]
        let result = try await service.insights(for: FoodPreferences(calorieGoal: 1_800, allergies: ["peanut"]), meals: meals)
        precondition(result.status == "low_protein" && result.summary.hasPrefix("You're low on protein"))
        precondition(result.foods == [Insights.Food(title: "Greek yogurt", why: "Easy protein.", kcal: 180, proteinG: 17), Insights.Food(title: "Apple")])
        precondition(result.workouts == [Insights.Workout(title: "Brisk walk", why: "Gentle.", minutes: 20, intensity: "light")])

        let sent = StubURLProtocol.capturedRequest!
        precondition(sent.url?.absoluteString == "http://ai-server:8000/insights" && sent.httpMethod == "POST")
        precondition(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: requestBody(sent)) as! [String: Any]
        let user = body["user"] as! [String: Any]
        precondition(user["calorie_goal"] as? Int == 1_800 && user["allergies"] as? [String] == ["peanut"] && user["diet"] == nil)
        let sentMeals = body["meals"] as! [[String: Any]]
        precondition(sentMeals.count == 1 && sentMeals[0]["name"] as? String == "Toast" && sentMeals[0]["kcal"] as? Double == 420)
        precondition(sentMeals[0]["protein_g"] as? Double == 8 && sentMeals[0]["sodium_mg"] as? Double == 450 && sentMeals[0]["fiber_g"] as? Double == 4)

        StubURLProtocol.status = 503
        StubURLProtocol.payload = Data(#"{"detail":"The insights server isn't running."}"#.utf8)
        do {
            _ = try await service.insights(for: FoodPreferences(), meals: [])
            preconditionFailure("Expected 503")
        } catch BellAIServiceError.server(503, let message) {
            precondition(message == "The insights server isn't running.")
        }
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"{"nope":1}"#.utf8)
        do {
            _ = try await service.insights(for: FoodPreferences(), meals: [])
            preconditionFailure("Expected invalid response")
        } catch BellAIServiceError.invalidResponse {}
    }

    @MainActor
    private static func testMealPhotoResultStaysOutOfTheChat() async {
        let food = StubFood(), logger = StubLogger()
        food.summary = "That looks like eggs and toast: about 364 calories, 19 g protein, 25 g carbs and 20 g fat."
        food.nutrition = Nutrition(calories: 364, proteinGrams: 19)
        let meal = MealPhotoViewModel(foodService: food, logger: logger)
        precondition(meal.phase == .idle && !meal.isShown && !meal.isBusy)
        precondition(meal.begin(Data([9]), note: "  no sauce  "))
        precondition(meal.isShown && meal.phase == .analyzing && meal.isBusy)
        precondition(!meal.begin(Data([8]))) // one at a time
        await meal.analyzeStored()
        precondition(food.analyzed.count == 1 && food.analyzed[0].jpeg == Data([9]) && food.analyzed[0].note == "no sauce")
        guard case .result(let result) = meal.phase else { preconditionFailure("expected a result") }
        precondition(result.summary == food.summary && result.current == Nutrition(calories: 364, proteinGrams: 19) && !result.isEdited && !result.isLogged)
        precondition(!meal.isBusy && meal.isShown && logger.logged.isEmpty) // nothing is logged until the person says so

        // no note sends none, and needs the food service
        meal.dismiss()
        precondition(!meal.isShown && meal.phase == .idle)
        precondition(meal.begin(Data([7])))
        await meal.analyzeStored()
        precondition(food.analyzed[1].note == nil)
        precondition(!MealPhotoViewModel().begin(Data([9])))

        // the chat has no photo of its own, and a reply is never read aloud
        let speech = StubSpeech()
        let chat = ChatViewModel(speech: speech, model: "test-model")
        precondition(chat.conversation.isEmpty && speech.clips.isEmpty)
    }

    @MainActor
    private static func testEditingMealLogsIt() async {
        let food = StubFood(), logger = StubLogger()
        food.summary = "That looks like eggs and toast: about 364 calories, 19 g protein, 25 g carbs and 20 g fat."
        food.nutrition = Nutrition(calories: 364, proteinGrams: 19)
        let meal = MealPhotoViewModel(foodService: food, logger: logger)
        precondition(meal.begin(Data([9]), note: "eggs and toast"))
        await meal.analyzeStored()

        // anything off is refused and logs nothing
        for bad in [Nutrition(calories: 0, proteinGrams: 10), Nutrition(calories: 10_001, proteinGrams: 10),
                    Nutrition(calories: 300, proteinGrams: -1), Nutrition(calories: 300, proteinGrams: 1_001)] {
            let accepted = await meal.correctAndLog(bad)
            precondition(!accepted)
        }
        precondition(logger.logged.isEmpty)

        // saving a correction logs the meal with it, and the reply shows the new numbers
        let accepted = await meal.correctAndLog(Nutrition(calories: 450, proteinGrams: 25))
        precondition(accepted)
        precondition(logger.logged.count == 1 && logger.logged[0].nutrition == Nutrition(calories: 450, proteinGrams: 25) && logger.logged[0].name == "eggs and toast")
        guard case .result(let result) = meal.phase else { preconditionFailure("expected a result") }
        precondition(result.isLogged && result.isEdited && result.reported == Nutrition(calories: 364, proteinGrams: 19))
        precondition(result.summary == "That looks like eggs and toast: about 450 calories, 25 g protein, 25 g carbs and 20 g fat.")

        // logged once, so a second edit or log doesn't add it again
        let again = await meal.correctAndLog(Nutrition(calories: 500, proteinGrams: 30))
        precondition(!again)
        await meal.log()
        precondition(logger.logged.count == 1)

        // wording the app doesn't recognise still shows the correction
        var soup = MealResult(MealAnalysis(summary: "Looks like soup.", nutrition: Nutrition(calories: 200, proteinGrams: 8)))
        precondition(soup.correct(to: Nutrition(calories: 250, proteinGrams: 10)))
        precondition(soup.summary == "Looks like soup. Corrected to 250 calories and 10 g protein.")
        // a second correction starts from what the model said, so the notes don't pile up
        precondition(soup.correct(to: Nutrition(calories: 300, proteinGrams: 12)))
        precondition(soup.summary == "Looks like soup. Corrected to 300 calories and 12 g protein.")
        precondition(soup.correct(to: Nutrition(calories: 200, proteinGrams: 8)) && !soup.isEdited)
    }

    @MainActor
    private static func testLoggingAsIsAndFailures() async {
        let food = StubFood(), logger = StubLogger()
        food.summary = "About 300 calories, 12 g protein."
        food.nutrition = Nutrition(calories: 300, proteinGrams: 12)
        let meal = MealPhotoViewModel(foodService: food, logger: logger)

        // log as it is, with no note the meal is just called a meal
        precondition(meal.begin(Data([9])))
        await meal.analyzeStored()
        await meal.log()
        precondition(logger.logged.map(\.nutrition) == [Nutrition(calories: 300, proteinGrams: 12)] && logger.logged[0].name == "Meal")
        guard case .result(let result) = meal.phase else { preconditionFailure("expected a result") }
        precondition(result.isLogged && !result.isEdited && meal.logError == nil)

        // when Apple Health says no, the edit stays and logging can be tried again
        meal.dismiss()
        precondition(meal.begin(Data([9])))
        await meal.analyzeStored()
        logger.error = MealLoggingError.notAllowed
        let accepted = await meal.correctAndLog(Nutrition(calories: 350, proteinGrams: 14))
        precondition(accepted && meal.logError != nil && logger.logged.count == 1)
        guard case .result(let refused) = meal.phase else { preconditionFailure("expected a result") }
        precondition(!refused.isLogged && refused.current == Nutrition(calories: 350, proteinGrams: 14))
        logger.error = nil
        await meal.log()
        precondition(meal.logError == nil && logger.logged.count == 2 && logger.logged[1].nutrition.calories == 350)

        // nothing was found, so there is nothing to log
        meal.dismiss()
        food.nutrition = nil
        precondition(meal.begin(Data([9])))
        await meal.analyzeStored()
        await meal.log()
        guard case .result(let empty) = meal.phase else { preconditionFailure("expected a result") }
        precondition(empty.current == nil && logger.logged.count == 2)
        let none = await meal.correctAndLog(Nutrition(calories: 100, proteinGrams: 1))
        precondition(!none)

        // nowhere to log to
        let lonely = MealPhotoViewModel(foodService: food)
        food.nutrition = Nutrition(calories: 300, proteinGrams: 12)
        precondition(lonely.begin(Data([9])))
        await lonely.analyzeStored()
        await lonely.log()
        precondition(lonely.logError != nil)
    }

    @MainActor
    private static func testMealPhotoFailuresAndDismissing() async {
        let food = StubFood()
        let meal = MealPhotoViewModel(foodService: food, logger: StubLogger())
        food.analyzeError = BellAIServiceError.http(503)
        precondition(meal.begin(Data([9])))
        await meal.analyzeStored()
        guard case .failed(let message) = meal.phase else { preconditionFailure("expected a failure") }
        precondition(!message.isEmpty && !meal.isBusy && meal.isShown)

        food.analyzeError = CancellationError()
        meal.dismiss()
        precondition(meal.begin(Data([9])))
        await meal.analyzeStored()
        guard case .failed(let cancelled) = meal.phase else { preconditionFailure("expected a failure") }
        precondition(cancelled.contains("cancelled"))

        // closed before the answer came back, so the answer is dropped
        food.analyzeError = nil
        food.nutrition = Nutrition(calories: 300, proteinGrams: 12)
        meal.dismiss()
        precondition(meal.begin(Data([9])))
        meal.dismiss()
        await meal.analyzeStored()
        precondition(meal.phase == .idle && !meal.isShown && !meal.isBusy)
    }

    private static func testServerSettings() {
        typealias Service = ServerSettings.Service
        let defaults = UserDefaults(suiteName: "bellai-server-settings-check")!
        defaults.removePersistentDomain(forName: "bellai-server-settings-check")
        defer { defaults.removePersistentDomain(forName: "bellai-server-settings-check") }
        func address(_ service: Service) -> String { ServerSettings.address(service, defaults: defaults) }
        func kept() -> [String] { defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("server.") }.sorted() }

        precondition(address(.chat) == "ai-server:11434" && address(.voice) == "ai-server:8000" && address(.data) == "ai-server:8001")
        let normal: [Service: Int] = [.chat: 11434, .voice: 8000, .data: 8001]

        // one address for everything, like a NetBird or local network address
        precondition(ServerSettings.save(host: " 192.168.1.20 ", ports: normal, defaults: defaults) == nil)
        precondition(address(.chat) == "192.168.1.20:11434" && address(.voice) == "192.168.1.20:8000" && address(.data) == "192.168.1.20:8001")
        precondition(kept() == ["server.host"])

        // a port of its own, and the others stay as they were
        precondition(ServerSettings.save(host: "100.64.0.5", ports: [.chat: 11434, .voice: 9000, .data: 8001], defaults: defaults) == nil)
        precondition(address(.chat) == "100.64.0.5:11434" && address(.voice) == "100.64.0.5:9000")
        precondition(kept() == ["server.host", "server.port.voice"])

        // back to what the build asks for keeps nothing, so a new build's defaults still apply
        precondition(ServerSettings.save(host: "ai-server", ports: normal, defaults: defaults) == nil)
        precondition(kept().isEmpty && address(.voice) == "ai-server:8000")

        // anything wrong is refused and what was saved stays
        precondition(ServerSettings.save(host: "10.0.0.2", ports: normal, defaults: defaults) == nil)
        for host in ["", "  ", "http://10.0.0.3", "10.0.0.3:8000", "10.0.0.3/path", "my mac"] {
            precondition(ServerSettings.save(host: host, ports: normal, defaults: defaults) != nil, "\(host)")
        }
        for port in [0, -1, 65536] {
            precondition(ServerSettings.save(host: "10.0.0.3", ports: [.chat: port, .voice: 8000, .data: 8001], defaults: defaults) != nil)
        }
        precondition(address(.chat) == "10.0.0.2:11434")

        ServerSettings.reset(defaults: defaults)
        precondition(kept().isEmpty && address(.data) == "ai-server:8001")
    }

    @MainActor
    private static func testTasksReloadAfterServerChange() async {
        let store = StubStore()
        store.stored = ["tasks": [["id": UUID().uuidString, "title": "First server", "isDone": false]]]
        let model = TasksViewModel(store: store)
        await model.load()
        precondition(model.tasks.map(\.title) == ["First server"])

        // a different server has different tasks, and load() alone would keep the old ones
        store.stored = ["tasks": [["id": UUID().uuidString, "title": "Second server", "isDone": false]]]
        await model.load()
        precondition(model.tasks.map(\.title) == ["First server"])
        await model.reload()
        precondition(model.tasks.map(\.title) == ["Second server"] && model.isLoaded)
    }

    @MainActor
    private static func testServerConnectionHealth(session: URLSession) async {
        let monitor = ServerConnectionMonitor(session: session)
        precondition(!monitor.isConnected)
        for (status, payload, connected) in [
            (200, #"{"version":"0.40.4"}"#, true),
            (200, #"{"version":""}"#, false),
            (503, #"{"version":"0.40.4"}"#, false),
            (200, #"{"unexpected":true}"#, false),
            (200, "invalid JSON", false)
        ] {
            StubURLProtocol.status = status
            StubURLProtocol.payload = Data(payload.utf8)
            await monitor.check()
            precondition(monitor.isConnected == connected)
        }
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"{"version":"0.40.4"}"#.utf8)
        await monitor.check()
        precondition(monitor.isConnected)
        monitor.reset()
        precondition(!monitor.isConnected)
        precondition(StubURLProtocol.capturedRequest?.url?.absoluteString == "http://ai-server:11434/api/version")
    }

    @MainActor
    private static func testMicrophoneSubmissionAndCancellation() async {
        let microphone = StubMicrophone()
        let api = StubService()
        let model = ChatViewModel(service: api, microphone: microphone, model: "test")
        model.toggleMicrophone()
        while microphone.continuation == nil { await Task.yield() }
        precondition(model.isListening && !model.isSubmitting)
        microphone.complete(nil)
        while model.isListening { await Task.yield() }
        precondition(api.requests.isEmpty && model.conversation.isEmpty)
        precondition(model.errorMessage?.contains("didn't hear") == true) // not silently nothing
        model.errorMessage = nil

        model.toggleMicrophone()
        while microphone.continuation == nil { await Task.yield() }
        microphone.complete("  Spoken question  ")
        while model.isListening || model.isSubmitting { await Task.yield() }
        precondition(api.requests.count == 1)
        precondition(model.conversation.map(\.content) == ["Spoken question", "Mock reply"])
        precondition(!model.isListening)

        model.toggleMicrophone()
        while microphone.continuation == nil { await Task.yield() }
        microphone.complete("Follow up")
        while model.isListening || model.isSubmitting { await Task.yield() }
        precondition(api.requests.last?.messages.count == 3)

        model.toggleMicrophone()
        while microphone.continuation == nil { await Task.yield() }
        model.stopMicrophone()
        await Task.yield()
        precondition(!model.isListening && api.requests.count == 2 && model.errorMessage == nil)

        model.toggleMicrophone()
        while microphone.continuation == nil { await Task.yield() }
        precondition(model.validateAndStoreRequest("Keyboard takes over"))
        precondition(!model.isListening && microphone.continuation == nil)
        await model.submitStoredRequest()
        precondition(api.requests.count == 3)
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
    private static func testFoodAnalysisHTTP(session: URLSession) async throws {
        let service = HTTPFoodAnalysisService(baseURL: URL(string: "http://ai-server:8000")!, session: session)
        StubURLProtocol.status = 200
        StubURLProtocol.payload = Data(#"{"summary":"Roughly 500 calories.","items":[],"totals":{}}"#.utf8)
        let meal = try await service.analyze(jpeg: Data([1]), note: "lunch")
        precondition(meal == MealAnalysis(summary: "Roughly 500 calories.", nutrition: nil))
        // the calories come from the totals, rounded, and nothing found means none
        StubURLProtocol.payload = Data(#"{"summary":"About 364 calories.","items":[],"totals":{"kcal":363.6,"protein_g":18.8}}"#.utf8)
        let rounded = try await service.analyze(jpeg: Data([1]), note: nil)
        precondition(rounded.nutrition == Nutrition(calories: 364, proteinGrams: 19))
        // the other nutrients come along for the recommendations, and are zero when the server doesn't say
        StubURLProtocol.payload = Data(#"{"summary":"About 364 calories.","items":[],"totals":{"kcal":363.6,"protein_g":18.8,"carbs_g":25.2,"fat_g":20.1,"fiber_g":2.9,"sugar_g":5.9,"sodium_mg":752.8}}"#.utf8)
        let detailed = try await service.analyze(jpeg: Data([1]), note: nil)
        precondition(detailed.nutrients == MealNutrients(kcal: 363.6, proteinG: 18.8, carbsG: 25.2, fatG: 20.1, fiberG: 2.9, sugarG: 5.9, sodiumMg: 752.8))
        StubURLProtocol.payload = Data(#"{"summary":"About 10 calories.","items":[],"totals":{"kcal":10}}"#.utf8)
        let bare = try await service.analyze(jpeg: Data([1]), note: nil)
        precondition(bare.nutrients == MealNutrients(kcal: 10))
        StubURLProtocol.payload = Data(#"{"summary":"About 10 calories.","items":[],"totals":{"kcal":10}}"#.utf8)
        let noProtein = try await service.analyze(jpeg: Data([1]), note: nil)
        precondition(noProtein.nutrition == Nutrition(calories: 10, proteinGrams: 0))
        StubURLProtocol.payload = Data(#"{"summary":"No nutrition info.","items":[],"totals":{"kcal":null}}"#.utf8)
        let none = try await service.analyze(jpeg: Data([1]), note: nil)
        precondition(none.nutrition == nil)
        StubURLProtocol.payload = Data(#"{"summary":"Roughly 500 calories.","items":[],"totals":{}}"#.utf8)
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
