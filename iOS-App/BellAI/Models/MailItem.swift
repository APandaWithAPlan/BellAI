import Foundation

// one email as the mail server saw it: who it is from and the model's notes, never the email itself
struct MailItem: Identifiable, Equatable, Decodable {
    enum Importance: String, Decodable {
        case high, normal, low

        // anything the server adds later is treated as normal
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Importance(rawValue: raw) ?? .normal
        }
    }

    let id: Int
    let account: String
    let received: Date?
    let sender: String
    let subject: String
    let importance: Importance
    let summary: String
    let action: String // what you need to do, empty if nothing
    let due: String // as written in the email, empty if none

    private enum CodingKeys: String, CodingKey {
        case id, account, received, sender, subject, importance, summary, action, due
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        account = try values.decodeIfPresent(String.self, forKey: .account) ?? ""
        received = ISO8601DateFormatter().date(from: try values.decodeIfPresent(String.self, forKey: .received) ?? "")
        sender = try values.decodeIfPresent(String.self, forKey: .sender) ?? ""
        subject = try values.decodeIfPresent(String.self, forKey: .subject) ?? ""
        importance = try values.decodeIfPresent(Importance.self, forKey: .importance) ?? .normal
        summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
        action = try values.decodeIfPresent(String.self, forKey: .action) ?? ""
        due = try values.decodeIfPresent(String.self, forKey: .due) ?? ""
    }

    init(id: Int, account: String = "", received: Date? = nil, sender: String, subject: String,
         importance: Importance = .normal, summary: String = "", action: String = "", due: String = "") {
        self.id = id
        self.account = account
        self.received = received
        self.sender = sender
        self.subject = subject
        self.importance = importance
        self.summary = summary
        self.action = action
        self.due = due
    }

    // "Ana Lopez <ana@example.com>" is shown as "Ana Lopez"
    var senderName: String {
        MailAddress.name(sender)
    }
}

// a reply or new email BellAI wrote, which is only sent once someone approves it
struct MailDraft: Identifiable, Equatable, Decodable {
    let id: Int
    let account: String
    let to: String
    let subject: String
    let body: String
    let replyTo: Int? // the id of the email it answers, nil for a new one
    let status: String

    private enum CodingKeys: String, CodingKey {
        case id, account, to, subject, body, status
        case replyTo = "reply_to"
    }

    init(id: Int, account: String = "", to: String, subject: String, body: String, replyTo: Int? = nil, status: String = "pending") {
        self.id = id
        self.account = account
        self.to = to
        self.subject = subject
        self.body = body
        self.replyTo = replyTo
        self.status = status
    }
}

enum MailAddress {
    // the name part of a From line, or the address if there is no name
    nonisolated static func name(_ sender: String) -> String {
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.lastIndex(of: "<") else { return trimmed }
        let name = trimmed[..<open].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
        if !name.isEmpty { return name }
        return trimmed[trimmed.index(after: open)...].trimmingCharacters(in: CharacterSet(charactersIn: "> "))
    }

    // just enough to catch a typo before asking the server, which checks it again
    nonisolated static func looksValid(_ address: String) -> Bool {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let dot = parts[1].lastIndex(of: "."),
              dot != parts[1].startIndex, parts[1].index(after: dot) != parts[1].endIndex else { return false }
        return !address.contains(where: \.isWhitespace)
    }
}
