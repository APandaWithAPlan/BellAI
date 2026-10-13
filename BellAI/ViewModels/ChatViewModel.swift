import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {
    private(set) var pendingRequest: ChatRequest?
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let service: any BellAIService
    private let model: String

    init(service: (any BellAIService)? = nil, model: String? = nil) {
        self.service = service ?? HTTPBellAIService()
        let configuredModel = Bundle.main.object(forInfoDictionaryKey: "OLLAMA_MODEL") as? String
        self.model = model ?? (configuredModel?.isEmpty == false ? configuredModel! : "gemma4:31b")
    }

    /// Validates and snapshots a request in memory, reserving one submission at a time.
    @discardableResult
    func validateAndStoreRequest(_ text: String) -> Bool {
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
        pendingRequest = ChatRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: message)],
            stream: false
        )
        isSubmitting = true
        return true
    }

    func submitStoredRequest() async {
        guard isSubmitting, let request = pendingRequest else { return }
        defer { isSubmitting = false }
        do {
            let response = try await service.send(request)
            // Do not log authorization headers or configuration values.
            print("[Ollama] model: \(response.model), done: \(response.done)")
            print("[Ollama] response: \(response.message.content)")
        } catch is CancellationError {
            // A cancelled task does not need an error alert.
        } catch {
            errorMessage = error.localizedDescription
            print("[Ollama] error: \(error.localizedDescription)")
        }
    }
}
