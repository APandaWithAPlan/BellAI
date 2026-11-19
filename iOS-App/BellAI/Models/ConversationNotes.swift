import Foundation

// what BellAI took from one conversation
nonisolated struct ConversationNotes: Codable, Equatable, Sendable {
    var summary: String
    var actionItems: [String]
    var topics: [String]
    var people: [String]
    var comment: String // BellAI's own remark on it

    init(summary: String, actionItems: [String] = [], topics: [String] = [], people: [String] = [], comment: String = "") {
        self.summary = summary
        self.actionItems = actionItems
        self.topics = topics
        self.people = people
        self.comment = comment
    }

    // a model that leaves a field out still gives usable notes
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
        actionItems = try values.decodeIfPresent([String].self, forKey: .actionItems) ?? []
        topics = try values.decodeIfPresent([String].self, forKey: .topics) ?? []
        people = try values.decodeIfPresent([String].self, forKey: .people) ?? []
        comment = try values.decodeIfPresent(String.self, forKey: .comment) ?? ""
    }

    // the notes of the parts of a long recording as one set: the summaries and comments in order,
    // and each item once, the first time it was said
    static func merge(_ parts: [ConversationNotes]) -> ConversationNotes {
        func once(_ items: [String]) -> [String] {
            var seen = Set<String>()
            return items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        }
        func joined(_ texts: [String]) -> String {
            texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        return ConversationNotes(
            summary: joined(parts.map(\.summary)),
            actionItems: once(parts.flatMap(\.actionItems)),
            topics: once(parts.flatMap(\.topics)),
            people: once(parts.flatMap(\.people)),
            comment: joined(parts.map(\.comment))
        )
    }
}

// one recording from the clip-on recorder, once it has been turned into text. kept as `<recording>.json` next to the audio
nonisolated struct RecordingEntry: Codable, Equatable, Identifiable, Sendable {
    // fewer characters than this is room noise or a stray word, not a conversation
    static let minimumSpeechCharacters = 40

    let name: String // the audio file without .wav
    let receivedAt: Date
    var transcript: String
    var notes: ConversationNotes?

    var id: String { name }
    var hasSpeech: Bool { transcript.count >= Self.minimumSpeechCharacters }
}

nonisolated enum TranscriptChunker {
    // a model can only read so much at once, so an hour of talk goes in parts. cut after a sentence where there is one
    static func chunks(_ text: String, maxCharacters: Int) -> [String] {
        var chunks: [String] = []
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)[...]
        while rest.count > maxCharacters {
            let limit = rest.index(rest.startIndex, offsetBy: maxCharacters)
            let window = rest[..<limit]
            let cut = window.lastIndex { ".?!".contains($0) }.map { window.index(after: $0) }
                ?? window.lastIndex(of: " ").map { window.index(after: $0) }
                ?? limit
            chunks.append(String(rest[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines))
            rest = rest[cut...].drop { $0 == " " || $0 == "\n" }
        }
        if !rest.isEmpty { chunks.append(String(rest)) }
        return chunks
    }
}
