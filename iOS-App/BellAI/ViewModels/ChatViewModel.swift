import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    private(set) var pendingRequest: ChatRequest?
    private(set) var isSubmitting = false
    private(set) var response: ChatResponse?
    private(set) var responseError: String?
    private(set) var conversation: [ConversationEntry] = []
    var errorMessage: String?

    // speaker toggle, turning it off stops any audio that's playing
    var isSpeakerEnabled: Bool {
        get { speakerOn }
        set {
            speakerOn = newValue
            if !newValue { speech?.stop() }
        }
    }
    var isSpeaking: Bool { speech?.isSpeaking ?? false }

    private var speakerOn = true
    private let service: any BellAIService
    private let voiceService: (any VoiceStreamService)?
    private let speech: (any SpeechPlaying)?
    private let model: String

    // no voiceService/speech = text only
    init(
        service: (any BellAIService)? = nil,
        voiceService: (any VoiceStreamService)? = nil,
        speech: (any SpeechPlaying)? = nil,
        model: String? = nil
    ) {
        self.service = service ?? HTTPBellAIService()
        self.voiceService = voiceService
        self.speech = speech
        let configuredModel = (Bundle.main.object(forInfoDictionaryKey: "OLLAMA_MODEL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model ?? (configuredModel?.isEmpty == false && configuredModel?.hasPrefix("$(") == false ? configuredModel! : "qwen3.5:4b-q4_K_M")
    }

    /// Validates and snapshots a request in memory, reserving one submission at a time.
    @discardableResult
    func validateAndStoreRequest(_ text: String, startsNewSession: Bool = false) -> Bool {
        guard !isSubmitting else { return false }
        errorMessage = nil
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            errorMessage = "Enter a message before sending."
            return false
        }
        guard message.count <= 4_000 else {
            errorMessage = "Keep your message to 4,000 characters or fewer."
            return false
        }
        response = nil
        responseError = nil
        speech?.stop()
        if startsNewSession { conversation.removeAll() }
        conversation.append(ConversationEntry(kind: .user, content: message))
        pendingRequest = ChatRequest(
            model: model,
            messages: conversation.compactMap(\.apiMessage),
            stream: false
        )
        isSubmitting = true
        return true
    }

    @discardableResult
    func startNewSession(with text: String) -> Bool {
        validateAndStoreRequest(text, startsNewSession: true)
    }

    func submitStoredRequest() async {
        guard isSubmitting, let request = pendingRequest else { return }
        defer { isSubmitting = false }
        // try the voice server first
        if speakerOn, let voiceService, let speech, await streamSpokenReply(request, from: voiceService, to: speech) {
            return
        }
        do {
            let response = try await service.send(request)
            self.response = response
            conversation.append(ConversationEntry(kind: .assistant, content: response.message.content))
            // Do not log authorization headers or configuration values.
            print("[Ollama] model: \(response.model), done: \(response.done)")
            print("[Ollama] response: \(response.message.content)")
        } catch is CancellationError {
            responseError = "The request was cancelled. Please try again."
            conversation.append(ConversationEntry(kind: .error, content: responseError!))
        } catch {
            responseError = error.localizedDescription
            conversation.append(ConversationEntry(kind: .error, content: error.localizedDescription))
            print("[Ollama] error: \(error.localizedDescription)")
        }
    }

    // streams text in while the audio plays
    // returns false if the voice server gave us nothing, so the caller can fall back to plain text
    private func streamSpokenReply(
        _ request: ChatRequest,
        from voiceService: any VoiceStreamService,
        to speech: any SpeechPlaying
    ) async -> Bool {
        var reply = ""
        var entryIndex: Int?
        do {
            for try await event in voiceService.stream(request) {
                switch event {
                case .text(let delta):
                    reply += delta
                    if let index = entryIndex {
                        conversation[index].content = reply
                    } else {
                        conversation.append(ConversationEntry(kind: .assistant, content: reply))
                        entryIndex = conversation.count - 1
                    }
                case .sentence(_, _, let audio):
                    if speakerOn { speech.enqueue(audio) } // muted mid reply = drop it
                case .done:
                    guard entryIndex != nil else { return false } // done with no text, fall back
                    response = ChatResponse(
                        model: request.model,
                        message: ChatMessage(role: "assistant", content: reply),
                        done: true
                    )
                    print("[Voice] model: \(request.model), reply: \(reply)")
                    return true
                }
            }
            throw VoiceStreamError.endedEarly
        } catch {
            print("[Voice] error: \(error.localizedDescription)")
            guard entryIndex != nil else { return false } // nothing showed up yet, fall back
            let message = error is CancellationError
                ? "The request was cancelled. Please try again."
                : error.localizedDescription
            responseError = message
            conversation.append(ConversationEntry(kind: .error, content: message))
            return true
        }
    }
}
