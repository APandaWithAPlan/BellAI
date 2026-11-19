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
    @State private var recorder: RecorderReceiver
    @State private var conversations: ConversationsViewModel
    @State private var music = MusicViewModel(music: AppleMusicService(), log: HTTPMusicLogService(), workout: WorkoutIntensityService())

    init() {
        // the photo flow records meals in the journal, and the recommendations are worked out from it
        let journal = MealJournal()
        _meal = State(initialValue: MealPhotoViewModel(foodService: HTTPFoodAnalysisService(), logger: standardMealLogger(), journal: journal))
        _insights = State(initialValue: InsightsViewModel(service: HTTPInsightsService(), journal: journal))
        // what the recorder uploads is turned into text and notes in the folder it saves to
        let recorder = RecorderReceiver()
        _recorder = State(initialValue: recorder)
        _conversations = State(initialValue: ConversationsViewModel(directory: recorder.directory, transcriber: AppleRecordingTranscriber(), analyzer: ConversationNotesService()))
    }

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.97)
                .ignoresSafeArea()

            if selectedTab == .home {
                if homeSection == .main {
                    HomeView(tasks: tasks, mail: mail, conversations: conversations, firstName: profile.firstName, lastName: profile.lastName, isSubmitting: chat.isSubmitting || meal.isBusy, onMicrophoneTap: {
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
                WellnessView(insights: insights, music: music, isSubmitting: chat.isSubmitting || meal.isBusy, onSubmitPhoto: submitPhoto)
            } else if selectedTab == .settings {
                SettingsView(profile: profile, recorder: recorder, onServerSaved: {
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
            async let loggingMusic: Void = music.syncPlays()
            async let hearing: Void = conversations.processNew() // what the recorder sent while the app was closed
            await tasks.load()
            await loadingMail
            await loggingMusic
            await hearing
        }
        .sheet(isPresented: Binding(get: { meal.isShown }, set: { if !$0 { meal.dismiss() } })) {
            MealResultView(model: meal)
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .bell { chat.stopMicrophone() }
        }
        .onChange(of: recorder.recordingCount) { _, _ in
            Task { await conversations.processNew() } // a recording just arrived
        }
        .onChange(of: scenePhase) { _, phase in
            recorder.setActive(phase == .active) // the recorder can only upload while the app is open
            if phase == .background {
                chat.stopMicrophone()
                music.stopFollowing() // heart rate and motion can't be read while the app is closed
            }
            if phase == .active {
                Task { await mail.refresh() } // new mail comes in while the app is closed
                Task { await music.syncPlays() } // and songs get played
                Task { await conversations.processNew() }
            }
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
