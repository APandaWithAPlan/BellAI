import SwiftUI

struct BellConversationView: View {
    var conversation: [ConversationEntry] = []

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            if conversation.isEmpty {
                Text("Start a conversation using the keyboard below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(conversation) { entry in
                BellMessageCardView(
                    position: entry.kind == .user ? .trailing : .leading,
                    title: title(for: entry),
                    symbol: entry.kind == .error ? "exclamationmark.triangle" : "sparkles",
                    message: entry.content,
                    subtext: entry.kind == .user ? "Typed message" : entry.kind == .error ? "You can try again using the input below." : ""
                ) {
                    if entry.kind != .error {
                        ShareLink(item: entry.content) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .id(entry.id)
            }
        }
    }

    private func title(for entry: ConversationEntry) -> String {
        switch entry.kind {
        case .user: "YOU"
        case .assistant: "BELL"
        case .error: "BELL · REQUEST FAILED"
        }
    }
}

#Preview {
    ScrollView {
        BellConversationView(conversation: [
            ConversationEntry(kind: .user, content: "Hello Bell"),
            ConversationEntry(kind: .assistant, content: "Hello! How can I help?"),
            ConversationEntry(kind: .user, content: "Suggest a cozy evening routine.")
        ])
        .padding(20)
    }
    .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
