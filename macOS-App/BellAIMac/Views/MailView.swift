import SwiftUI

// the emails BellAI has read, the replies waiting for your approval, and writing a new one
struct MailView: View {
    @Environment(Features.self) private var features
    @State private var sheet: MailSheet?

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
        let model = features.mail
        Page("Mail", subtitle: model.isLoaded ? model.cardDetail : nil) {
            HStack(spacing: 4) {
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
                    .disabled(model.isLoading)
                Button { sheet = .compose } label: { Image(systemName: "square.and.pencil") }
                    .help("Write an email")
            }
        } content: {
            VStack(alignment: .leading, spacing: 24) {
                if let error = model.loadError {
                    ProblemLine(text: error) { Task { await model.refresh() } }
                }
                if !model.isLoaded && model.loadError == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if model.isLoaded && model.mail.isEmpty && model.drafts.isEmpty {
                    EmptyNote(symbol: "envelope", text: "No mail yet. The Mac reads your inboxes in the background.")
                }
                if !model.drafts.isEmpty {
                    section("Waiting for your approval") {
                        Rows(items: model.drafts) { draft in
                            Button { sheet = .draft(draft) } label: { DraftRow(draft: draft) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !model.mail.isEmpty {
                    section("Inbox") {
                        Rows(items: model.mail) { item in
                            Button { sheet = .message(item) } label: { MailRow(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await model.refresh() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .message(let item): MessageSheet(item: item) { self.sheet = .draft($0) }
            case .draft(let draft): DraftSheet(draft: draft) { self.sheet = nil }
            case .compose: ComposeSheet { self.sheet = .draft($0) }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}

private struct MailRow: View {
    let item: MailItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.importance == .high ? Theme.accent : item.importance == .normal ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.2))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.senderName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if let received = item.received {
                        Text(received.formatted(.relative(presentation: .named)))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Text(item.subject).font(.system(size: 13)).lineLimit(1)
                if !item.summary.isEmpty {
                    Text(item.summary).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                }
                if !item.action.isEmpty {
                    Label(item.due.isEmpty ? item.action : "\(item.action) (\(item.due))", systemImage: "checkmark.circle")
                        .font(.system(size: 12)).foregroundStyle(Theme.accent).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.importance == .high ? "Important" : "")
    }
}

private struct DraftRow: View {
    let draft: MailDraft

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.line").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("To \(MailAddress.name(draft.to))").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(draft.subject).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("Review").font(.system(size: 13)).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// the sheets share a title bar with a button to close
private struct SheetFrame<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let close: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(close) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            content
        }
        .padding(20)
        .frame(width: 540)
        .background(Theme.background)
    }
}

// what to say in a reply or new email
private struct SayField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .lineLimit(3...8)
            .padding(12)
            .panel()
    }
}

private struct MessageSheet: View {
    @Environment(Features.self) private var features
    let item: MailItem
    let onDraft: (MailDraft) -> Void
    @State private var saying = ""

    var body: some View {
        let model = features.mail
        SheetFrame(title: item.senderName, close: "Close") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.subject).font(.system(size: 15, weight: .semibold))
                    if !item.summary.isEmpty { Text(item.summary).foregroundStyle(.secondary) }
                    if !item.action.isEmpty {
                        Label(item.due.isEmpty ? item.action : "\(item.action) (\(item.due))", systemImage: "checkmark.circle")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .textSelection(.enabled)
                .font(.system(size: 14))

                Text("Reply").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                SayField(text: $saying, prompt: "What should the reply say? For example: yes, Thursday works")
                if let error = model.actionError { ProblemLine(text: error) }
                HStack {
                    if model.isWorking { ProgressView().controlSize(.small); Text("Writing, which can take up to a minute…").foregroundStyle(.secondary) }
                    Spacer()
                    Button("Write Reply") {
                        Task { if let draft = await model.writeReply(to: item, saying: saying) { onDraft(draft) } }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(model.isWorking || saying.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { model.actionError = nil }
    }
}

private struct ComposeSheet: View {
    @Environment(Features.self) private var features
    let onDraft: (MailDraft) -> Void
    @State private var address = ""
    @State private var saying = ""

    var body: some View {
        let model = features.mail
        SheetFrame(title: "New Email", close: "Cancel") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("", text: $address, prompt: Text("To: name@example.com"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(12)
                    .panel()
                SayField(text: $saying, prompt: "What should the email say?")
                if let error = model.actionError { ProblemLine(text: error) }
                HStack {
                    if model.isWorking { ProgressView().controlSize(.small); Text("Writing, which can take up to a minute…").foregroundStyle(.secondary) }
                    Spacer()
                    Button("Write Email") {
                        Task { if let draft = await model.writeNew(to: address, saying: saying) { onDraft(draft) } }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(model.isWorking || address.isEmpty || saying.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { model.actionError = nil }
    }
}

// an email is only sent when you press Send here
private struct DraftSheet: View {
    @Environment(Features.self) private var features
    let draft: MailDraft
    let onClose: () -> Void

    var body: some View {
        let model = features.mail
        SheetFrame(title: "Review Email", close: "Close") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("To", value: draft.to)
                    LabeledContent("Subject", value: draft.subject)
                    Divider()
                    ScrollView {
                        Text(draft.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                }
                .font(.system(size: 14))
                .textSelection(.enabled)
                .padding(12)
                .panel()

                Text("Read the address and the text before you send. An email can contain text written to trick an AI.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if let error = model.actionError { ProblemLine(text: error) }
                HStack {
                    Button("Discard", role: .destructive) {
                        Task { if await model.discard(draft) { onClose() } }
                    }
                    Spacer()
                    Button("Send") {
                        Task { if await model.send(draft) { onClose() } }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .disabled(model.isWorking)
            }
        }
        .onAppear { model.actionError = nil }
    }
}
