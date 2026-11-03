import SwiftUI

private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)
private let accent = Color(red: 1, green: 0.18, blue: 0.45)

// title, and a button to close, for the sheets in this file
private struct SheetHeader: View {
    let title: String
    let close: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(ink)
            Spacer()
            Button(close, action: onClose)
                .font(.headline)
                .foregroundStyle(accent)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// what to say in a reply or new email, and the button that has BellAI write it
private struct SayField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundStyle(muted), axis: .vertical)
            .lineLimit(2...6)
            .foregroundStyle(ink)
            .tint(accent)
            .modifier(WhiteCard(border: accent))
    }
}

private struct WriteButton: View {
    let title: String
    let isWorking: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking { ProgressView().tint(.white) }
                Text(isWorking ? "Writing…" : title).font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(accent.opacity(isEnabled || isWorking ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isEnabled || isWorking)
    }
}

// an email, with what BellAI made of it and a way to answer
struct MailMessageSheet: View {
    var model: MailViewModel
    let item: MailItem
    let onDraft: (MailDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saying = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Email", close: "Done") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.subject)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ink)
                        Text(item.sender)
                            .font(.subheadline)
                            .foregroundStyle(muted)
                        if let received = item.received {
                            Text(received.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(muted)
                        }
                    }
                    if !item.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(item.importance == .high ? "Important" : "Summary", systemImage: "sparkles")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(accent)
                            Text(item.summary)
                                .foregroundStyle(ink)
                            if !item.action.isEmpty {
                                Text(item.due.isEmpty ? item.action : "\(item.action) Due \(item.due).")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(accent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(WhiteCard())
                    }
                    Text("Reply")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(muted)
                    SayField(text: $saying, prompt: "What should it say? Like: yes, Thursday works")
                    WriteButton(title: "Write reply", isWorking: model.isWorking, isEnabled: !trimmed.isEmpty) {
                        Task {
                            if let draft = await model.writeReply(to: item, saying: saying) { onDraft(draft) }
                        }
                    }
                    if let error = model.actionError {
                        Text(error).font(.footnote).foregroundStyle(accent)
                    }
                    Text("BellAI writes it and shows it to you first. Nothing is sent until you approve it.")
                        .font(.footnote)
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .onAppear { model.actionError = nil }
    }

    private var trimmed: String { saying.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// a new email: who it is to, and what to say
struct MailComposeSheet: View {
    var model: MailViewModel
    let onDraft: (MailDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var saying = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "New email", close: "Cancel") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("", text: $address, prompt: Text("To: name@example.com").foregroundStyle(muted))
                        .foregroundStyle(ink)
                        .tint(accent)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .modifier(WhiteCard())
                    SayField(text: $saying, prompt: "What should it say? Like: ask if dinner Saturday is still on")
                    WriteButton(title: "Write email", isWorking: model.isWorking, isEnabled: canWrite) {
                        Task {
                            if let draft = await model.writeNew(to: address, saying: saying) { onDraft(draft) }
                        }
                    }
                    if let error = model.actionError {
                        Text(error).font(.footnote).foregroundStyle(accent)
                    }
                    Text("BellAI writes it and shows it to you first. Nothing is sent until you approve it.")
                        .font(.footnote)
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .onAppear { model.actionError = nil }
    }

    private var canWrite: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty && !saying.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// the approval step: who it goes to and exactly what it says, then send or discard
struct MailDraftSheet: View {
    var model: MailViewModel
    let draft: MailDraft
    let onClose: () -> Void

    // false once it was sent or discarded, here or somewhere else like Discord
    private var isOpen: Bool { model.drafts.contains { $0.id == draft.id } }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Review email", close: "Close", onClose: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        field("To", draft.to)
                        field("Subject", draft.subject)
                        Divider()
                        Text(draft.body)
                            .foregroundStyle(ink)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(WhiteCard(border: accent))

                    if isOpen {
                        Button {
                            Task { if await model.send(draft) { onClose() } }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isWorking { ProgressView().tint(.white) }
                                Text("Send to \(draft.to)")
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(accent, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(model.isWorking)

                        Button("Discard") {
                            Task { if await model.discard(draft) { onClose() } }
                        }
                        .font(.headline)
                        .foregroundStyle(muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(model.isWorking)
                    } else {
                        Text("This one is finished. It was sent or discarded, so it can't be sent again.")
                            .font(.subheadline)
                            .foregroundStyle(muted)
                    }
                    if let error = model.actionError {
                        Text(error).font(.footnote).foregroundStyle(accent)
                    }
                    Text("Read the address and the text before you send. Nothing leaves your Mac until you press Send.")
                        .font(.footnote)
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .onAppear { model.actionError = nil }
    }

    private func field(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(muted)
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(ink).textSelection(.enabled)
        }
    }
}
