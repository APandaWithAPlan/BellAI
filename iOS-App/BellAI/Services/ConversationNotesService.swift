import Foundation
import FoundationModels

private let instructions = """
You are BellAI, a personal assistant that overhears the user's day through a clip-on microphone. \
You are given part of a transcript of conversations, with no speaker names and some mistakes from speech recognition. \
Say only what the transcript supports, and leave a field empty rather than guess. \
Action items are things someone said they will do or need to do, as short phrases. \
The comment is one short, kind remark or suggestion from you to the user about what was said.
"""

// takes the notes with Apple Intelligence on the phone, or with the BellAI server when the phone has none
@MainActor
struct ConversationNotesService: TranscriptAnalyzing {
    private let server: any BellAIService

    init(server: (any BellAIService)? = nil) {
        self.server = server ?? HTTPBellAIService()
    }

    func notes(from transcript: String) async throws -> ConversationNotes {
        if #available(iOS 26, *), SystemLanguageModel.default.isAvailable {
            return try await Self.appleNotes(transcript)
        }
        return try await serverNotes(transcript)
    }

    @available(iOS 26, *)
    private static func appleNotes(_ transcript: String) async throws -> ConversationNotes {
        // a new session for each part, so earlier parts don't use up what the model can hold
        let session = LanguageModelSession(instructions: instructions)
        let made = try await session.respond(to: transcript, generating: GeneratedNotes.self).content
        return ConversationNotes(summary: made.summary, actionItems: made.actionItems, topics: made.topics, people: made.people, comment: made.comment)
    }

    private func serverNotes(_ transcript: String) async throws -> ConversationNotes {
        let ask = """
        \(instructions)
        Reply with only JSON like {"summary": "two sentences", "actionItems": [], "topics": [], "people": [], "comment": ""}.

        Transcript:
        \(transcript)
        """
        let reply = try await server.send(ChatRequest(model: ChatViewModel.defaultModel, messages: [ChatMessage(role: "user", content: ask)], stream: false))
        // models like to wrap JSON in prose or a code fence, so take what is between the outer braces
        let text = reply.message.content
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let notes = try? JSONDecoder().decode(ConversationNotes.self, from: Data(text[open...close].utf8)) else {
            throw BellAIServiceError.invalidResponse
        }
        return notes
    }
}

@available(iOS 26, *)
@Generable
private struct GeneratedNotes {
    @Guide(description: "One or two sentences on what was talked about")
    var summary: String
    @Guide(description: "Things someone said they will do or need to do, as short phrases. Empty if none.")
    var actionItems: [String]
    @Guide(description: "Up to four short topic names")
    var topics: [String]
    @Guide(description: "Names of people mentioned. Empty if none.")
    var people: [String]
    @Guide(description: "One short, kind remark or suggestion from BellAI to the user about the conversation")
    var comment: String
}
