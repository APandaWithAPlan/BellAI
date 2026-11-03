import SwiftUI

// the emails BellAI has read, the replies waiting for your approval, and writing a new one
struct MailView: View {
    @Bindable var model: MailViewModel
    @State private var sheet: MailSheet?

    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)
    private let accent = Color(red: 1, green: 0.18, blue: 0.45)

    enum MailSheet: Identifiable {
        case message(MailItem)
        case draft(MailDraft)
        case compose

        var id: String {
            switch self {
            case .message(let item): "mail-\(item.id)"
            case .draft(let draft): "draft-\(draft.id)"
            case .compose: "compose"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mail")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ink)
                Spacer()
                Button { sheet = .compose } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Write an email")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if !model.isLoaded {
                loadingState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .task { await model.refresh() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .message(let item):
                MailMessageSheet(model: model, item: item) { self.sheet = .draft($0) }
            case .draft(let draft):
                MailDraftSheet(model: model, draft: draft) { self.sheet = nil }
            case .compose:
                MailComposeSheet(model: model) { self.sheet = .draft($0) }
            }
        }
    }

    @ViewBuilder
    private var loadingState: some View {
        if let error = model.loadError {
            VStack(spacing: 12) {
                Label("Couldn't load your mail", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(accent)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await model.refresh() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 24)
        } else {
            ProgressView("Loading mail…")
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let error = model.loadError {
                    Text("Couldn't refresh: \(error)")
                        .font(.footnote)
                        .foregroundStyle(accent)
                }
                if !model.drafts.isEmpty {
                    sectionTitle("Waiting for your approval")
                    ForEach(model.drafts) { draft in
                        Button { sheet = .draft(draft) } label: { draftRow(draft) }
                            .buttonStyle(.plain)
                    }
                    sectionTitle("Inbox")
                }
                if model.mail.isEmpty {
                    Text("No emails yet. BellAI checks your inboxes every few minutes, and only looks at the last two days the first time.")
                        .font(.subheadline)
                        .foregroundStyle(muted)
                }
                ForEach(model.mail) { item in
                    Button { sheet = .message(item) } label: { MailRow(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await model.refresh() }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(muted)
            .padding(.top, 6)
    }

    private func draftRow(_ draft: MailDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("To \(draft.to)", systemImage: "paperplane")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
            Text(draft.subject)
                .font(.subheadline)
                .foregroundStyle(ink)
            Text(draft.body)
                .font(.footnote)
                .foregroundStyle(muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WhiteCard(border: accent))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Review and send")
    }
}

private struct MailRow: View {
    let item: MailItem

    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)
    private let accent = Color(red: 1, green: 0.18, blue: 0.45)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.importance == .high ? accent : item.importance == .normal ? muted.opacity(0.6) : muted.opacity(0.25))
                .frame(width: 9, height: 9)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.senderName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let received = item.received {
                        Text(received.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                            .font(.caption)
                            .foregroundStyle(muted)
                    }
                }
                Text(item.subject)
                    .font(.subheadline)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.footnote)
                        .foregroundStyle(muted)
                        .lineLimit(2)
                }
                if !item.action.isEmpty {
                    Text(item.due.isEmpty ? item.action : "\(item.action) · due \(item.due)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(accent)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(WhiteCard())
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.importance == .high ? "Important" : "")
        .accessibilityHint("Open")
    }
}

// the white rounded card that mail and preferences sit on, white even in dark mode like the rest of the app
struct WhiteCard: ViewModifier {
    var border = Color(red: 0.91, green: 0.88, blue: 0.90)

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(border, lineWidth: 0.75)
            }
    }
}

#Preview {
    NavigationStack {
        MailView(model: MailViewModel(service: HTTPMailService()))
    }
}
