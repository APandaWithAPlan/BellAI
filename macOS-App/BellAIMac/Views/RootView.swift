import SwiftUI

struct RootView: View {
    @Environment(ChatStore.self) private var store
    @Environment(ServerController.self) private var servers
    @Environment(Features.self) private var features
    @State private var showServers = false

    var body: some View {
        NavigationSplitView {
            SidebarView(showServers: $showServers)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            switch features.section {
            case .chat:
                if let conversation = store.current {
                    ChatView(conversation: conversation)
                        .id(conversation.id)
                }
            case .tasks: TasksView()
            case .mail: MailView()
            case .meals: MealsView()
            case .captures: CapturesView()
            case .recorder: RecorderSetupView()
            }
        }
        .task { await servers.poll() }
        .sheet(isPresented: $showServers) { ServerPanel() }
    }
}

struct Avatar: View {
    let size: CGFloat

    var body: some View {
        Image("Avatar")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

private enum SidebarItem: Hashable {
    case feature(Feature)
    case chat(Conversation.ID)
}

struct SidebarView: View {
    @Environment(ChatStore.self) private var store
    @Environment(Features.self) private var features
    @Binding var showServers: Bool

    // the tools, then the conversations
    private var selection: Binding<SidebarItem?> {
        Binding {
            features.section == .chat ? store.selection.map(SidebarItem.chat) : .feature(features.section)
        } set: { item in
            switch item {
            case .chat(let id): store.selection = id; features.section = .chat
            case .feature(let feature): features.section = feature
            case nil: break
            }
        }
    }

    // conversations grouped by when they were last used, newest first
    private var sections: [(title: String, chats: [Conversation])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.conversations) { chat -> String in
            if calendar.isDateInToday(chat.updated) { return "Today" }
            if calendar.isDateInYesterday(chat.updated) { return "Yesterday" }
            if let days = calendar.dateComponents([.day], from: chat.updated, to: .now).day, days < 7 { return "Previous 7 Days" }
            return "Older"
        }
        return ["Today", "Yesterday", "Previous 7 Days", "Older"].compactMap { title in
            grouped[title].map { (title, $0) }
        }
    }

    // what needs you: replies to approve, else important emails
    private var mailBadge: Int {
        features.mail.drafts.isEmpty ? features.mail.important.count : features.mail.drafts.count
    }

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(Feature.allCases.filter { $0 != .chat }) { feature in
                    Label(feature.title, systemImage: feature.symbol)
                        .badge(feature == .mail ? mailBadge : 0)
                        .tag(SidebarItem.feature(feature))
                }
            }
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.chats) { chat in
                        Text(chat.title)
                            .lineLimit(1)
                            .padding(.vertical, 2)
                            .tag(SidebarItem.chat(chat.id))
                            .contextMenu {
                                Button("Delete", role: .destructive) { store.delete(chat.id) }
                            }
                    }
                } header: {
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .onDeleteCommand {
            if features.section == .chat, let id = store.selection { store.delete(id) }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Avatar(size: 24)
                    Text("BellAI").font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                NewChatButton()
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                ServerStatusRow(showPanel: $showServers)
            }
            .background(Theme.sidebar)
        }
    }
}

private struct NewChatButton: View {
    @Environment(ChatStore.self) private var store
    @Environment(Features.self) private var features
    @State private var hovering = false

    var body: some View {
        Button {
            store.newChat()
            features.section = .chat
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").foregroundStyle(Theme.accent)
                Text("New Chat")
                Spacer()
                Text("⌘N").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.surface.opacity(hovering ? 1 : 0.65), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("New chat")
    }
}
