import Foundation
import Observation

// every conversation, which one is open, and the reply being written. kept in a JSON file in Application Support
@MainActor @Observable
final class ChatStore {
    enum Listening { case idle, starting, listening, transcribing }

    var conversations: [Conversation] = []
    var selection: Conversation.ID?
    private(set) var streamingID: Conversation.ID?
    private(set) var models: [String] = []
    private(set) var listening = Listening.idle
    // something to tell the person about the voice: the server isn't answering, or nothing was heard
    private(set) var notice: String?
    let speech = SpeechPlayer()
    // what BellAI should know when you chat, like your open tasks and important emails
    var context: (() -> String?)?

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var micTask: Task<Void, Never>?
    @ObservationIgnored private let microphone = MicrophoneService()
    @ObservationIgnored private let fileURL: URL

    var current: Conversation? { conversations.first { $0.id == selection } }

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BellAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("conversations.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = saved
        }
        newChat()
        refreshModels()
    }

    // an empty chat is reused, so they don't pile up
    func newChat() {
        if let empty = conversations.first(where: { $0.messages.isEmpty }) {
            selection = empty.id
            return
        }
        let chat = Conversation()
        conversations.insert(chat, at: 0)
        selection = chat.id
    }

    func delete(_ id: Conversation.ID) {
        if streamingID == id { stop() }
        conversations.removeAll { $0.id == id }
        if selection == id { selection = conversations.first?.id }
        if selection == nil { newChat() }
        save()
    }

    func refreshModels() {
        Task { models = (try? await ChatClient()?.models()) ?? [] }
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard streamingID == nil, !text.isEmpty, let id = selection, let i = index(of: id) else { return }
        stopListening()
        if conversations[i].messages.isEmpty { conversations[i].title = String(text.prefix(48)) }
        conversations[i].messages.append(Message(role: .user, text: text))
        conversations[i].messages.append(Message(role: .assistant, text: ""))
        conversations[i].updated = .now
        conversations.sort { $0.updated > $1.updated }
        speech.stop()
        notice = nil
        streamingID = id
        save()
        streamTask = Task { await reply(in: id) }
    }

    func stop() {
        streamTask?.cancel()
        speech.stop()
    }

    // one tap to start listening, another to send what was said, or to cancel while it is being turned into text
    func toggleMicrophone() {
        switch listening {
        case .listening:
            microphone.finish()
        case .starting, .transcribing:
            stopListening()
        case .idle:
            guard streamingID == nil else { return }
            speech.stop()
            notice = nil
            listening = .starting
            micTask = Task {
                do {
                    let text = try await microphone.listen(
                        onReady: { self.listening = .listening },
                        onTranscribing: { self.listening = .transcribing })
                    listening = .idle
                    if let text { send(text) } else { notice = "I didn't hear anything. Click the microphone and try again." }
                } catch {
                    listening = .idle
                    if !(error is CancellationError) { notice = error.localizedDescription }
                }
            }
        }
    }

    private func stopListening() {
        micTask?.cancel()
        micTask = nil
        microphone.cancel()
        listening = .idle
    }

    private func reply(in id: Conversation.ID) async {
        defer { finish(id) }
        do {
            guard let client = ChatClient() else { throw ChatClientError.badAddress }
            // the history without the empty reply being filled in, or earlier errors
            var history = Array((current(id)?.messages.dropLast() ?? []).filter { !$0.failed })
            // goes on the last message, not a system one, so the voice server keeps its own system prompt
            if let context = context?(), let last = history.indices.last {
                history[last].text = "[Context, mention only if relevant: \(context)]\n\n\(history[last].text)"
            }

            if UserDefaults.standard.object(forKey: Prefs.speak) as? Bool ?? true {
                var wroteText = false
                do {
                    let request = ChatRequest(model: "", messages: history.map { ChatMessage(role: $0.role.rawValue, content: $0.text) }, stream: true)
                    for try await event in WebSocketVoiceService().stream(request) {
                        switch event {
                        case .text(let piece): wroteText = true; edit(id) { $0.text += piece }
                        case .sentence(_, _, let wav): speech.enqueue(wav)
                        case .done: break
                        }
                    }
                    return
                } catch {
                    if Task.isCancelled || wroteText { throw error }
                    // nothing came back, so ask the chat model for text instead
                    notice = "The voice server isn't answering, so replies are text only. Start it from Servers."
                }
            }

            let model = try await resolveModel(client)
            for try await piece in client.stream(model: model, messages: history) {
                edit(id) { $0.text += piece }
            }
        } catch {
            if Task.isCancelled { return }
            edit(id) { reply in
                if reply.text.isEmpty {
                    reply.text = error.localizedDescription
                    reply.failed = true
                } else {
                    reply.text += "\n\n(\(error.localizedDescription))"
                }
            }
        }
    }

    private func resolveModel(_ client: ChatClient) async throws -> String {
        let chosen = UserDefaults.standard.string(forKey: Prefs.model)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !chosen.isEmpty { return chosen }
        if let first = models.first { return first }
        guard let first = try await client.models().first else { throw ChatClientError.noModel }
        return first
    }

    private func finish(_ id: Conversation.ID) {
        // stopped before the first word: nothing to keep
        if let i = index(of: id), let last = conversations[i].messages.last,
           last.role == .assistant, last.text.isEmpty {
            conversations[i].messages.removeLast()
        }
        streamingID = nil
        streamTask = nil
        save()
    }

    private func current(_ id: Conversation.ID) -> Conversation? { conversations.first { $0.id == id } }

    private func index(of id: Conversation.ID) -> Int? { conversations.firstIndex { $0.id == id } }

    private func edit(_ id: Conversation.ID, _ change: (inout Message) -> Void) {
        guard let i = index(of: id), !conversations[i].messages.isEmpty else { return }
        change(&conversations[i].messages[conversations[i].messages.count - 1])
    }

    private func save() {
        let kept = conversations.filter { !$0.messages.isEmpty }
        if let data = try? JSONEncoder().encode(kept) { try? data.write(to: fileURL, options: .atomic) }
    }
}
