import SwiftUI

struct BellView: View {
    var conversation: [ConversationEntry] = []
    var isSubmitting = false
    var onSubmitPrompt: (String) -> Bool = { _ in false }
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var isSpeakerEnabled = true
    @State private var showsKeyboardInput = false
    @State private var typedPrompt = ""
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            BellHeaderView(
                subtitle: isSubmitting ? "Thinking…" : "Ready to help",
                onClose: onClose,
                onOpenSettings: onOpenSettings
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        BellConversationView(conversation: conversation)
                        Color.clear.frame(height: 1).id("conversationEnd")
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: conversation.last?.id) { _, _ in
                    proxy.scrollTo("conversationEnd", anchor: .bottom)
                }
                .onChange(of: isPromptFocused) { _, focused in
                    if focused { proxy.scrollTo("conversationEnd", anchor: .bottom) }
                }
            }

            VStack(spacing: 12) {
                BellInputControlsView(
                    isSpeakerEnabled: $isSpeakerEnabled,
                    isKeyboardVisible: showsKeyboardInput,
                    onKeyboardTap: toggleKeyboardInput
                )

                if showsKeyboardInput {
                    HStack(spacing: 8) {
                        TextField("Type a message…", text: $typedPrompt)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .focused($isPromptFocused)
                            .submitLabel(.send)
                            .onSubmit(submitFollowUp)
                            .accessibilityLabel("Message BellAI")
                            .task { isPromptFocused = true }

                        Button(action: submitFollowUp) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting || typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send message")
                    }
                    .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
                    .tint(Color(red: 0.92, green: 0.24, blue: 0.49))
                    .padding(.leading, 14)
                    .padding(.trailing, 4)
                    .padding(.vertical, 4)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(red: 0.92, green: 0.24, blue: 0.49), lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleKeyboardInput() {
        showsKeyboardInput.toggle()
        if !showsKeyboardInput { isPromptFocused = false }
    }

    private func submitFollowUp() {
        guard !isSubmitting, onSubmitPrompt(typedPrompt) else { return }
        typedPrompt = ""
        isPromptFocused = false
    }
}

#Preview {
    BellView(onClose: {}, onOpenSettings: {})
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
