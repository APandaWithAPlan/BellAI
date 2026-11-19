import AVFoundation
import SwiftUI
import Observation

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    var text: String
}

// plays wav replies one at a time, and says when each one has finished
@MainActor
final class WavPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?

    func play(_ wav: Data) async {
        guard let player = try? AVAudioPlayer(data: wav) else { return }
        self.player = player
        player.delegate = self
        await withCheckedContinuation { continuation in
            finished = continuation
            if !player.play() { finish() }
        }
    }

    func stop() {
        player?.stop()
        finish()
    }

    private func finish() {
        finished?.resume()
        finished = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if player === self.player { finish() } }
    }
}

// talks to the chat model: straight to the llm server (which answers like Ollama), or through the
// voice server when the speaker is on, which sends each sentence back as audio too
@MainActor
@Observable
final class ChatModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isSending = false  // stays true until the reply has finished playing, when it is spoken
    private(set) var error: String?
    private(set) var speaks = true
    private var task: Task<Void, Never>?
    private let player = WavPlayer()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120  // the first reply waits on the model loading
        return URLSession(configuration: config)
    }()

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        messages.append(ChatMessage(isUser: true, text: text))
        messages.append(ChatMessage(isUser: false, text: ""))
        isSending = true
        error = nil
        task = Task { await reply() }
    }

    func clear() {
        task?.cancel()
        player.stop()
        messages = []
        isSending = false
        error = nil
    }

    // turning it off mid-reply cuts the audio, and the rest of the reply stays text
    func toggleSpeaker() {
        speaks.toggle()
        if !speaks { player.stop() }
    }

    private func reply() async {
        defer { if !Task.isCancelled { isSending = false } }  // a cleared chat has already reset it
        let history = messages.dropLast().map { ["role": $0.isUser ? "user" : "assistant", "content": $0.text] }
        do {
            if speaks {
                try await replySpoken(history)
            } else {
                try await replyText(history)
            }
        } catch {
            if Task.isCancelled { return }
            self.error = speaks
                ? "Can't reach the voice server. Start the servers in the Status tab, or turn the speaker off."
                : "Can't reach the chat model. Start the servers in the Status tab."
        }
        if messages.last?.text.isEmpty == true { messages.removeLast() }
    }

    private func replyText(_ history: [[String: String]]) async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["messages": history, "stream": true])
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        for try await line in bytes.lines {
            guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(line.utf8)) else { continue }
            if let message = chunk.error { error = message; return }
            messages[messages.count - 1].text += chunk.message?.content ?? ""
        }
    }

    // the voice server sends text as it is written, then a wav per sentence
    private func replySpoken(_ history: [[String: String]]) async throws {
        let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:8000/ws")!)
        socket.maximumMessageSize = 16 * 1024 * 1024
        let (audio, queue) = AsyncStream.makeStream(of: Data.self)
        let playback = Task {
            for await wav in audio where speaks { await player.play(wav) }
        }
        defer { playback.cancel() }
        try await withTaskCancellationHandler {
            socket.resume()
            try await socket.send(.string(String(data: JSONSerialization.data(withJSONObject: ["messages": history]), encoding: .utf8) ?? ""))
            loop: while true {
                switch try await socket.receive() {
                case .data(let wav):
                    queue.yield(wav)
                case .string(let json):
                    guard let event = try? JSONDecoder().decode(SpokenEvent.self, from: Data(json.utf8)) else { continue }
                    switch event.type {
                    case "text": messages[messages.count - 1].text += event.delta ?? ""
                    case "error": error = event.message; break loop
                    case "done": break loop
                    default: break
                    }
                @unknown default:
                    break
                }
            }
            queue.finish()
            await playback.value  // the chat waits here until the last sentence has been said
            socket.cancel(with: .normalClosure, reason: nil)
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private struct Chunk: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message?
        let error: String?
    }

    private struct SpokenEvent: Decodable {
        let type: String
        let delta: String?
        let message: String?
    }
}

struct ChatView: View {
    let chat: ChatModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(chat.messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                        if let error = chat.error {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: chat.messages.last?.text) {
                    if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .overlay {
                    if chat.messages.isEmpty {
                        Text("Say something to the chat model")
                            .font(.caption)
                            .foregroundStyle(secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(action: chat.toggleSpeaker) {
                    Image(systemName: chat.speaks ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 13))
                        .frame(width: 32, height: 32)
                        .background(buttonBackground, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chat.speaks ? "Turn the speaker off" : "Turn the speaker on")

                TextField("Message", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($focused)
                    .onSubmit(submit)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(buttonBackground, in: Capsule())

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(green, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(chat.isSending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send")
            }

            if !chat.messages.isEmpty {
                Button("New chat") { chat.clear() }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(secondary)
            }
        }
        .onAppear { focused = true }
    }

    private func submit() {
        chat.send(draft)
        draft = ""
    }

    private func bubble(_ message: ChatMessage) -> some View {
        Text(message.text.isEmpty ? "..." : message.text)
            .font(.subheadline)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.isUser ? buttonBackground : .clear, in: RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}
