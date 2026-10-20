import SwiftUI
import Playgrounds

struct ContentView: View {
    @State private var selectedTab: BellAITab = .home
    @State private var chat = ChatViewModel(voiceService: WebSocketVoiceService(), speech: SpeechPlayer())

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.97)
                .ignoresSafeArea()

            if selectedTab == .home {
                HomeView(isSubmitting: chat.isSubmitting, onSubmitPrompt: submitHomePrompt)
            } else if selectedTab == .bell {
                BellView(
                    conversation: chat.conversation,
                    isSubmitting: chat.isSubmitting,
                    isSpeaking: chat.isSpeaking,
                    isSpeakerEnabled: $chat.isSpeakerEnabled,
                    onSubmitPrompt: submitFollowUpPrompt,
                    onClose: { selectedTab = .home },
                    onOpenSettings: { selectedTab = .settings }
                )
            } else {
                Text(selectedTab.rawValue)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavigationView(selection: $selectedTab)
        }
        .alert("Couldn't send message", isPresented: Binding(
            get: { chat.errorMessage != nil },
            set: { if !$0 { chat.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { chat.errorMessage = nil }
        } message: {
            Text(chat.errorMessage ?? "")
        }
    }

    private func submitHomePrompt(_ text: String) -> Bool {
        guard chat.startNewSession(with: text) else { return false }
        transitionToBellConversation()
        Task { await chat.submitStoredRequest() }
        return true
    }

    private func transitionToBellConversation() {
        selectedTab = .bell
    }

    private func submitFollowUpPrompt(_ text: String) -> Bool {
        guard chat.validateAndStoreRequest(text) else { return false }
        Task { await chat.submitStoredRequest() }
        return true
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
