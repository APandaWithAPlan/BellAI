import Foundation

struct Message: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, assistant }

    var id = UUID()
    let role: Role
    var text: String
    var failed = false // text is an error message, not part of the conversation
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "New chat"
    var messages: [Message] = []
    var updated = Date()
}

// UserDefaults keys shared by the store and Settings. where the servers are lives in ServerSettings
enum Prefs {
    static let model = "model"
    static let speak = "speak" // read replies aloud, on unless turned off
}
