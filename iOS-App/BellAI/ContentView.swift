import SwiftUI
import Playgrounds

struct ContentView: View {
    @State private var selectedTab: BellAITab = .home
    @State private var chat = ChatViewModel(voiceService: WebSocketVoiceService(), foodService: HTTPFoodAnalysisService(), speech: SpeechPlayer())
    @State private var tasks = TasksViewModel(store: FirebaseUserDataService())

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.97)
                .ignoresSafeArea()

            if selectedTab == .home {
                HomeView(isSubmitting: chat.isSubmitting, onSubmitPrompt: submitHomePrompt, onSubmitPhoto: submitHomePhoto)
            } else if selectedTab == .bell {
                BellView(
                    conversation: chat.conversation,
                    isSubmitting: chat.isSubmitting,
                    isSpeaking: chat.isSpeaking,
                    isSpeakerEnabled: $chat.isSpeakerEnabled,
                    onSubmitPrompt: submitFollowUpPrompt,
                    onSubmitPhoto: submitFollowUpPhoto,
                    onClose: { selectedTab = .home },
                    onOpenSettings: { selectedTab = .settings }
                )
            } else if selectedTab == .tasks {
                TasksView(model: tasks)
            } else {
                Text(selectedTab.rawValue)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavigationView(selection: $selectedTab)
        }
        .task {
            // BellAI gets your open tasks as context, so load them now, not when the tab opens
            chat.contextProvider = { [tasks] in tasks.openTaskSummary }
            await tasks.load()
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

    private func submitHomePhoto(_ jpeg: Data, note: String) -> Bool {
        guard chat.validateAndStorePhoto(jpeg, note: note, startsNewSession: true) else { return false }
        transitionToBellConversation()
        Task { await chat.submitStoredPhoto() }
        return true
    }

    private func submitFollowUpPhoto(_ jpeg: Data, note: String) -> Bool {
        guard chat.validateAndStorePhoto(jpeg, note: note) else { return false }
        Task { await chat.submitStoredPhoto() }
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
