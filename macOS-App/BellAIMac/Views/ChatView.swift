import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Prefs.speak) private var speak = true
    let conversation: Conversation

    private var streamingHere: Bool { store.streamingID == conversation.id }

    var body: some View {
        Group {
            if conversation.messages.isEmpty {
                welcome
            } else {
                transcript
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(conversationID: conversation.id)
        }
        .navigationTitle(conversation.title)
        .toolbar {
            ToolbarItem {
                Button {
                    speak.toggle()
                    if !speak { store.speech.stop() }
                } label: {
                    Image(systemName: speak ? "speaker.wave.2.fill" : "speaker.slash")
                        .foregroundStyle(speak ? Theme.accent : Color.secondary)
                }
                .help(speak ? "Reading replies aloud. Click to turn the voice off" : "Voice is off. Click to read replies aloud")
                .accessibilityLabel(speak ? "Turn voice off" : "Turn voice on")
            }
        }
        .toolbarBackground(Theme.background, for: .windowToolbar)
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Avatar(size: 72)
            Text("How can I help you today?")
                .font(.system(size: 22, weight: .semibold))
        }
        .padding(.bottom, 60)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 28) {
                    ForEach(conversation.messages) { message in
                        MessageRow(message: message, isWriting: streamingHere && message.id == conversation.messages.last?.id)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: conversation.messages.count)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: Theme.columnWidth + 56)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: conversation.messages.count) { proxy.scrollTo("end") }
            .onChange(of: conversation.messages.last?.text) { proxy.scrollTo("end") }
            .onAppear { proxy.scrollTo("end") }
        }
    }
}

private struct Composer: View {
    @Environment(ChatStore.self) private var store
    @FocusState private var focused: Bool
    @State private var text = ""
    let conversationID: Conversation.ID

    // a reply being written, or still being read aloud, can be stopped
    private var streamingHere: Bool { store.streamingID == conversationID || store.speech.isSpeaking }
    private var canSend: Bool {
        store.streamingID == nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if let notice = store.notice {
                Label(notice, systemImage: "speaker.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            field
        }
        .frame(maxWidth: Theme.columnWidth)
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .onAppear { focused = true }
    }

    private var micHelp: String {
        switch store.listening {
        case .idle: "Speak to BellAI"
        case .starting: "Starting the microphone. Click to cancel"
        case .listening: "Listening. Click to send what you said"
        case .transcribing: "Turning your voice into text. Click to cancel"
        }
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(store.listening == .listening ? "Listening…" : "Message BellAI", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit(submit)
                .padding(.vertical, 6)
            micButton
            sendButton
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background { RoundedRectangle(cornerRadius: 16).fill(Theme.surface) }
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(focused ? Theme.accent.opacity(0.6) : Theme.border) }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var micButton: some View {
        let idle = store.listening == .idle
        return Button(action: store.toggleMicrophone) {
            Image(systemName: idle ? "mic" : "mic.fill")
                .font(.system(size: 15))
                .foregroundStyle(idle ? Color.secondary : Theme.accent)
                .frame(width: 30, height: 30)
                .overlay {
                    if store.listening == .transcribing { ProgressView().controlSize(.small) }
                }
        }
        .buttonStyle(.plain)
        .disabled(store.streamingID != nil)
        .help(micHelp)
        .accessibilityLabel(micHelp)
    }

    private var sendButton: some View {
        let ready = streamingHere || canSend
        let label: String = streamingHere ? "Stop" : "Send"
        return Button {
            if streamingHere { store.stop() } else { submit() }
        } label: {
            Image(systemName: streamingHere ? "stop.fill" : "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ready ? Color.white : Color.secondary)
                .frame(width: 30, height: 30)
                .background { RoundedRectangle(cornerRadius: 9).fill(ready ? Theme.accent : Theme.border) }
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityLabel(label)
    }

    private func submit() {
        guard canSend else { return }
        store.send(text)
        text = ""
    }
}
