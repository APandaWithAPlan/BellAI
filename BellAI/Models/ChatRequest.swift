import Foundation

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
