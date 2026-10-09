import SwiftUI

struct BellView: View {
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var isSpeakerEnabled = true
    @State private var showsKeyboardInput = false
    @State private var typedPrompt = ""
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            BellHeaderView(onClose: onClose, onOpenSettings: onOpenSettings)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 16) {
                    BellListeningView()
                    BellConversationView()
                    BellInputControlsView(
                        isSpeakerEnabled: $isSpeakerEnabled,
                        isKeyboardVisible: showsKeyboardInput,
                        onKeyboardTap: {
                            showsKeyboardInput.toggle()
                            if !showsKeyboardInput {
                                isPromptFocused = false
                            }
                        }
                    )

                    if showsKeyboardInput {
                        TextField("Type a message…", text: $typedPrompt, axis: .vertical)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
                            .tint(Color(red: 0.92, green: 0.24, blue: 0.49))
                            .lineLimit(1...4)
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color(red: 0.92, green: 0.24, blue: 0.49), lineWidth: 1)
                            }
                            .focused($isPromptFocused)
                            .accessibilityLabel("Message Bell AI")
                            .task { isPromptFocused = true }
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    BellView(onClose: {}, onOpenSettings: {})
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
