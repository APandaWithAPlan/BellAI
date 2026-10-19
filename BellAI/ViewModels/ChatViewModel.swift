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

    private let service: any BellAIService
    private let model: String

    init(service: (any BellAIService)? = nil, model: String? = nil) {
        self.service = service ?? HTTPBellAIService()
        let configuredModel = (Bundle.main.object(forInfoDictionaryKey: "OLLAMA_MODEL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model ?? (configuredModel?.isEmpty == false && configuredModel?.hasPrefix("$(") == false ? configuredModel! : "qwen3:8b")
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
}
