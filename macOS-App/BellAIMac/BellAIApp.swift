import SwiftUI

@main
struct BellAIApp: App {
    @State private var store = ChatStore()
    @State private var servers = ServerController()
    @State private var features = Features()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(servers)
                .environment(features)
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    store.context = { [features] in features.chatContext }
                    await features.load()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    store.newChat()
                    features.section = .chat
                }
                .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(features)
        }
    }
}
