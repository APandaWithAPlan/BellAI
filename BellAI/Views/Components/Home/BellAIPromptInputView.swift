import SwiftUI

struct BellAIPromptInputView: View {
    @Binding var text: String
    var onMicrophoneTap: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .body) private var avatarSize = 38.0

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.white)
                .frame(width: avatarSize, height: avatarSize)
                .background(Color(red: 0.92, green: 0.24, blue: 0.49), in: Circle())
                .accessibilityHidden(true)

            TextField(
                "What can I help with?",
                text: $text,
                prompt: Text("What can I help with?")
                    .foregroundStyle(Color(red: 0.48, green: 0.43, blue: 0.46)),
                axis: .vertical
            )
            .font(.subheadline)
            .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .tint(accent)
            .accessibilityLabel("Message Bell AI")

            Button {
                onMicrophoneTap?()
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onMicrophoneTap == nil)
            .accessibilityLabel("Use microphone")
        }
        .padding(.leading, 9)
        .padding(.trailing, 1)
        .padding(.vertical, 6)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(accent, lineWidth: 1)
        }
    }
}

#Preview {
    @Previewable @State var text = ""

    BellAIPromptInputView(text: $text)
        .padding(20)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
