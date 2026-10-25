import AVFoundation
import SwiftUI
import Playgrounds

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: BellAITab = .home
    @State private var homeSection: HomeSection = .main
    @State private var bottomNavigationHeight: CGFloat = 56
    @State private var chat = ChatViewModel(voiceService: WebSocketVoiceService(), foodService: HTTPFoodAnalysisService(), speech: SpeechPlayer())
    @State private var tasks = TasksViewModel(store: FirebaseUserDataService())

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.97)
                .ignoresSafeArea()

            if selectedTab == .home {
                if homeSection == .main {
                    HomeView(isSubmitting: chat.isSubmitting, onMicrophoneTap: {
                        selectedTab = .bell
                        chat.toggleMicrophone(startsNewSession: true)
                    }, onSubmitPrompt: submitHomePrompt, onSubmitPhoto: submitHomePhoto)
                } else {
                    BriefingView()
                }
            } else if selectedTab == .bell {
                BellView(
                    conversation: chat.conversation,
                    isSubmitting: chat.isSubmitting,
                    isSpeaking: chat.isSpeaking,
                    isListening: chat.isListening,
                    isStartingMicrophone: chat.isStartingMicrophone,
                    onMicrophoneTap: { chat.toggleMicrophone() },
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
            VStack(spacing: 12) {
                if selectedTab == .home {
                    HomeSectionNavigationView(selection: $homeSection, height: bottomNavigationHeight * 2 / 3)
                        .padding(.horizontal, 20)
                }
                BottomNavigationView(selection: $selectedTab)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        bottomNavigationHeight = height
                    }
            }
        }
        .task {
            // BellAI gets your open tasks as context, so load them now, not when the tab opens
            chat.contextProvider = { [tasks] in tasks.openTaskSummary }
            await tasks.load()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .bell { chat.stopMicrophone() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { chat.stopMicrophone() }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            chat.stopMicrophone()
        }
        #endif
        .onDisappear { chat.stopMicrophone() }
        .alert("Couldn't complete request", isPresented: Binding(
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
