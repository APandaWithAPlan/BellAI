import SwiftUI

// what BellAI heard of the day through the clip-on recorder: a summary, things to do, and a remark on each conversation
struct ConversationsView: View {
    @Bindable var model: ConversationsViewModel

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Conversations").font(.largeTitle.weight(.bold))
                status
                ForEach(model.entries) { entry in
                    card(entry)
                }
                if model.entries.isEmpty && !model.isWorking && model.pendingCount == 0 {
                    Text("Nothing yet. Turn on Receive recordings in Settings, and conversations appear here after the recorder uploads them while BellAI is open.")
                        .font(.subheadline).foregroundStyle(muted)
                }
                Toggle(isOn: $model.deletesAudio) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete audio once it is text").font(.subheadline.weight(.medium))
                        Text("Saves about 115 MB for every hour recorded. The text and notes are kept. Can’t be undone.")
                            .font(.caption).foregroundStyle(muted)
                    }
                }
                .tint(accent)
                Text("Everything is turned into text and notes on this phone. Check that the people you record are comfortable with it, since the law on recording conversations varies by place.")
                    .font(.caption).foregroundStyle(muted)
            }
            .padding(20)
        }
        .foregroundStyle(ink)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .task { await model.processNew() }
        .alert("Conversations", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var status: some View {
        if model.isWorking {
            HStack(spacing: 12) {
                ProgressView()
                Text("Listening back to \(model.currentName ?? "a recording")…").font(.subheadline).foregroundStyle(muted)
            }
        } else if model.pendingCount > 0 {
            Button("Process \(model.pendingCount) waiting") { Task { await model.processNew(retryingFailed: true) } }
                .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
        }
    }

    // a short look at one conversation. a tap opens all of it, with the whole transcript
    private func card(_ entry: RecordingEntry) -> some View {
        NavigationLink {
            ConversationDetailView(model: model, id: entry.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.receivedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(muted)
                        .accessibilityHidden(true)
                }
                Text(preview(entry)).font(.subheadline).foregroundStyle(entry.hasSpeech ? ink : muted)
                    .lineLimit(3).multilineTextAlignment(.leading)
                if entry.hasSpeech {
                    Label("Transcript", systemImage: "text.alignleft").font(.caption).foregroundStyle(accent)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
        }
        .buttonStyle(.plain)
    }

    // the summary, or the start of what was said while the notes are still to come
    private func preview(_ entry: RecordingEntry) -> String {
        if let summary = entry.notes?.summary, !summary.isEmpty { return summary }
        return entry.transcript
    }
}

// one conversation in full: the notes, then everything that was said
struct ConversationDetailView: View {
    var model: ConversationsViewModel
    let id: String
    @Environment(\.dismiss) private var dismiss

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)

    var body: some View {
        // looked up each time, so notes that arrive while this is open appear
        if let entry = model.entries.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(entry.receivedAt.formatted(date: .abbreviated, time: .shortened)).font(.title2.weight(.bold))
                    if let notes = entry.notes { notesBlock(notes) }
                    else if entry.hasSpeech { Text("Notes are waiting.").font(.subheadline).foregroundStyle(muted) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcript").font(.title3.weight(.bold))
                        Text(entry.transcript)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
            }
            .foregroundStyle(ink)
            .background(Color(red: 0.97, green: 0.96, blue: 0.97))
            .toolbar {
                if !entry.transcript.isEmpty {
                    ToolbarItem { ShareLink(item: entry.transcript) }
                }
                ToolbarItem {
                    Button(role: .destructive) { model.delete(entry); dismiss() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete this conversation")
                }
            }
        } else {
            Text("This conversation was deleted.").foregroundStyle(muted)
        }
    }

    private func notesBlock(_ notes: ConversationNotes) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(notes.summary).font(.body)
            if !notes.actionItems.isEmpty { section("To do", notes.actionItems.map { "• \($0)" }.joined(separator: "\n")) }
            if !notes.topics.isEmpty { section("Topics", notes.topics.joined(separator: ", ")) }
            if !notes.people.isEmpty { section("People", notes.people.joined(separator: ", ")) }
            if !notes.comment.isEmpty { Text("“\(notes.comment)”").font(.subheadline.italic()).foregroundStyle(accent) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(muted)
            Text(text).font(.subheadline)
        }
    }
}
