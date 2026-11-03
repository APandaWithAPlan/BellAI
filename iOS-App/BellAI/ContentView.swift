import AVFoundation
import SwiftUI

struct ContentView: View {
    @State private var profile = ProfileViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: BellAITab = .home
    @State private var homeSection: HomeSection = .main
    @State private var bottomNavigationHeight: CGFloat = 56
    @State private var chat = ChatViewModel(voiceService: WebSocketVoiceService(), speech: SpeechPlayer())
    @State private var meal: MealPhotoViewModel
    @State private var insights: InsightsViewModel
    @State private var tasks = TasksViewModel(store: HTTPUserDataService())
    @State private var mail = MailViewModel(service: HTTPMailService())

    init() {
        // the photo flow records meals in the journal, and the recommendations are worked out from it
        let journal = MealJournal()
        _meal = State(initialValue: MealPhotoViewModel(foodService: HTTPFoodAnalysisService(), logger: standardMealLogger(), journal: journal))
        _insights = State(initialValue: InsightsViewModel(service: HTTPInsightsService(), journal: journal))
    }

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.97)
                .ignoresSafeArea()

            if selectedTab == .home {
                if homeSection == .main {
                    HomeView(tasks: tasks, mail: mail, firstName: profile.firstName, lastName: profile.lastName, isSubmitting: chat.isSubmitting || meal.isBusy, onMicrophoneTap: {
                        selectedTab = .bell
                        chat.toggleMicrophone(startsNewSession: true)
                    }, onSubmitPrompt: submitHomePrompt, onSubmitPhoto: submitPhoto)
                } else {
                    BriefingView(tasks: tasks)
                }
            } else if selectedTab == .bell {
                BellView(
                    conversation: chat.conversation,
                    isSubmitting: chat.isSubmitting || meal.isBusy,
                    isSpeaking: chat.isSpeaking,
                    isListening: chat.isListening,
                    isStartingMicrophone: chat.isStartingMicrophone,
                    isTranscribing: chat.isTranscribing,
                    onMicrophoneTap: { chat.toggleMicrophone() },
                    isSpeakerEnabled: $chat.isSpeakerEnabled,
                    onSubmitPrompt: submitFollowUpPrompt,
                    onSubmitPhoto: submitPhoto,
                    onClose: { selectedTab = .home },
                    onOpenSettings: { selectedTab = .settings }
                )
            } else if selectedTab == .activity {
                WellnessView(insights: insights, isSubmitting: chat.isSubmitting || meal.isBusy, onSubmitPhoto: submitPhoto)
            } else if selectedTab == .settings {
                SettingsView(profile: profile, onServerSaved: {
                    Task { await tasks.reload() }
                    Task { await mail.reload() }
                })
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
            // BellAI gets your open tasks and important emails as context, so load them now, not when the tab opens
            chat.contextProvider = { [tasks, mail] in
                let facts = [tasks.openTaskSummary, mail.importantSummary].compactMap { $0 }
                return facts.isEmpty ? nil : facts.joined(separator: ", and ")
            }
            async let loadingMail: Void = mail.refresh()
            await tasks.load()
            await loadingMail
        }
        .sheet(isPresented: Binding(get: { meal.isShown }, set: { if !$0 { meal.dismiss() } })) {
            MealResultView(model: meal)
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .bell { chat.stopMicrophone() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { chat.stopMicrophone() }
            if phase == .active { Task { await mail.refresh() } } // new mail comes in while the app is closed
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

    // a meal photo is answered where it was taken, in a sheet, and not spoken
    private func submitPhoto(_ jpeg: Data, note: String) -> Bool {
        guard !chat.isSubmitting, meal.begin(jpeg, note: note) else { return false }
        chat.stopMicrophone()
        Task { await meal.analyzeStored() }
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
