import SwiftUI

struct BellInputControlsView: View {
    @Binding var isSpeakerEnabled: Bool
    var isKeyboardVisible = false
    let onKeyboardTap: () -> Void
    var onMicrophoneTap: (() -> Void)? = nil

    private let accent = Color(red: 0.92, green: 0.24, blue: 0.49)
    private let buttonBackground = Color(red: 0.94, green: 0.92, blue: 0.93)
    private let foreground = Color(red: 0.48, green: 0.43, blue: 0.46)

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onKeyboardTap) {
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(isKeyboardVisible ? accent : foreground)
                    .frame(width: 44, height: 44)
                    .background(buttonBackground, in: Circle())
            }
            .accessibilityLabel(isKeyboardVisible ? "Hide keyboard input" : "Type a message")

            Spacer(minLength: 24)

            Button {
                onMicrophoneTap?()
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(accent, in: Circle())
                    .shadow(color: accent.opacity(0.20), radius: 18, y: 8)
            }
            .disabled(onMicrophoneTap == nil)
            .accessibilityLabel("Start voice input")

            Spacer(minLength: 24)

            Button {
                isSpeakerEnabled.toggle()
            } label: {
                Image(systemName: isSpeakerEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(foreground)
                    .frame(width: 44, height: 44)
                    .background(buttonBackground, in: Circle())
            }
            .accessibilityLabel(isSpeakerEnabled ? "Mute spoken responses" : "Enable spoken responses")
            .accessibilityValue(isSpeakerEnabled ? "On" : "Off")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 286)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

#Preview {
    @Previewable @State var isSpeakerEnabled = true

    BellInputControlsView(isSpeakerEnabled: $isSpeakerEnabled, onKeyboardTap: {})
        .padding(20)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
