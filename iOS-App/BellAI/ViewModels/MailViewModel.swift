import Foundation
import Observation

@MainActor
@Observable
final class MailViewModel {
    private(set) var mail: [MailItem] = []
    private(set) var drafts: [MailDraft] = []
    private(set) var isLoaded = false
    private(set) var isLoading = false
    private(set) var isWorking = false // writing, sending or discarding, one at a time
    var loadError: String? // why the list couldn't be loaded, shown in place of it
    var actionError: String? // why a draft couldn't be written or sent, shown with the draft

    private let service: any MailService
    private let limit = 50

    init(service: any MailService) {
        self.service = service
    }

    var important: [MailItem] { mail.filter { $0.importance == .high } }

    // for the card on Home
    var cardDetail: String {
        if loadError != nil { return "Offline" }
        guard isLoaded else { return "Loading…" }
        if !drafts.isEmpty { return drafts.count == 1 ? "1 to approve" : "\(drafts.count) to approve" }
        if !important.isEmpty { return "\(important.count) important" }
        return mail.isEmpty ? "No mail" : "All caught up"
    }

    // for the assistant, nil until loaded so it never hears "no mail" before we know. it's the model's own notes
    // about emails from other people, so it is worded as what they said and kept short
    var importantSummary: String? {
        guard isLoaded else { return nil }
        guard !important.isEmpty else { return "I have no important emails" }
        let shown = important.prefix(5).map { "\($0.senderName): \(String($0.summary.prefix(150)))" }.joined(separator: "; ")
        let extra = important.count > 5 ? " (and \(important.count - 5) more)" : ""
        return "my important emails are: \(shown)\(extra)"
    }

    // keeps what is shown if it fails, so a bad connection doesn't empty the screen
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let latest = service.recent(limit: limit)
            async let waiting = service.pendingDrafts()
            (mail, drafts) = try await (latest, waiting)
            isLoaded = true
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
    }

    // for after the server changed, what is there is a different mailbox
    func reload() async {
        mail = []
        drafts = []
        isLoaded = false
        loadError = nil
        await refresh()
    }

    // the draft to look at, nil if it couldn't be written (see actionError)
    func writeReply(to item: MailItem, saying: String) async -> MailDraft? {
        await write(saying: saying, to: nil, replyTo: item.id)
    }

    func writeNew(to address: String, saying: String) async -> MailDraft? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MailAddress.looksValid(address) else {
            actionError = "That doesn't look like an email address."
            return nil
        }
        return await write(saying: saying, to: address, replyTo: nil)
    }

    private func write(saying: String, to: String?, replyTo: Int?) async -> MailDraft? {
        let saying = saying.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isWorking else { return nil }
        guard !saying.isEmpty else {
            actionError = "Say what the email should say."
            return nil
        }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            let draft = try await service.writeDraft(saying: String(saying.prefix(1_000)), to: to, replyTo: replyTo)
            drafts.insert(draft, at: 0)
            return draft
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    // true once it has gone. the server only sends a draft once, so after a failure it is gone from the list either way
    func send(_ draft: MailDraft) async -> Bool {
        await decide(draft) { try await self.service.send(draft) }
    }

    func discard(_ draft: MailDraft) async -> Bool {
        await decide(draft) { try await self.service.discard(draft) }
    }

    private func decide(_ draft: MailDraft, _ action: () async throws -> Void) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            try await action()
            drafts.removeAll { $0.id == draft.id }
            return true
        } catch {
            actionError = error.localizedDescription
            if let latest = try? await service.pendingDrafts() { drafts = latest } // sent or discarded elsewhere, say from Discord
            return false
        }
    }
}
