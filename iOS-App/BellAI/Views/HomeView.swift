import SwiftUI

struct HomeView: View {
    var tasks: TasksViewModel
    var isSubmitting = false
    var onMicrophoneTap: (() -> Void)? = nil
    var onSubmitPrompt: (String) -> Bool = { _ in false }
    var onSubmitPhoto: (Data, String) -> Bool = { _, _ in false }
    @State private var prompt = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HomeHeaderView()
                    HomeFeatureCardsView(tasks: tasks)
                    BellAIPromptInputView(
                        text: $prompt,
                        isSubmitting: isSubmitting,
                        onSubmit: {
                            if onSubmitPrompt(prompt) { prompt = "" }
                        },
                        onMicrophoneTap: onMicrophoneTap,
                        onPhotoPicked: { jpeg in
                            if onSubmitPhoto(jpeg, prompt) { prompt = "" } // what's typed goes along as the note
                        }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.97, green: 0.96, blue: 0.97))
            .navigationTitle("Home")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }
}

#Preview {
    HomeView(tasks: TasksViewModel(store: PlannerPreviewStore()))
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
