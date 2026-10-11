import SwiftUI

struct BellHeaderView: View {
    var subtitle = "Ready to help"
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    private let foreground = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let buttonBackground = Color(red: 0.94, green: 0.92, blue: 0.93)

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .light))
                    .frame(width: 44, height: 44)
                    .background(buttonBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Bell")

            VStack(spacing: 4) {
                Text("Bell")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 0.10, green: 0.71, blue: 0.43))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.48, green: 0.43, blue: 0.46))
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Menu {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(buttonBackground, in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More Bell options")
        }
        .foregroundStyle(foreground)
    }
}

#Preview {
    BellHeaderView(onClose: {}, onOpenSettings: {})
        .padding(20)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
