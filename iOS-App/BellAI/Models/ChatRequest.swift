import Foundation

struct ConversationEntry: Identifiable, Equatable {
    enum Kind { case user, assistant, error }

    let id = UUID()
    let kind: Kind
    var content: String // grows while a reply streams in

    var apiMessage: ChatMessage? {
        switch kind {
        case .user: ChatMessage(role: "user", content: content)
        case .assistant: ChatMessage(role: "assistant", content: content)
        case .error: nil
        }
    }
}

struct ChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct ChatRequest: Codable, Equatable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

struct ChatResponse: Codable {
    let model: String
    let message: ChatMessage
    let done: Bool
}
