import SwiftUI

private enum Tab: String, CaseIterable {
    case status = "Status"
    case chat = "Chat"
}

struct MenuView: View {
    let monitor: ServerMonitor
    let chat: ChatModel
    @State private var tab = Tab.status

    var body: some View {
        VStack(spacing: 14) {
            Text("BellAI")
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Button(item.rawValue) { tab = item }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(tab == item ? buttonBackground : .clear, in: Capsule())
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }

            switch tab {
            case .status: StatusView(monitor: monitor)
            case .chat: ChatView(chat: chat)
            }

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(secondary)
        }
        .foregroundStyle(foreground)
        .padding(20)
        .frame(width: 320, height: 420)
        .background(panel)
        .environment(\.colorScheme, .light)
    }
}

@main
struct BellMenuApp: App {
    @State private var monitor = ServerMonitor()
    @State private var chat = ChatModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(monitor: monitor, chat: chat)
        } label: {
            Text("🐱")
                .task { await monitor.poll() }
        }
        .menuBarExtraStyle(.window)
    }
}
