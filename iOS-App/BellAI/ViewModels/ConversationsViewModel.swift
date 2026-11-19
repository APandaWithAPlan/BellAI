import Foundation
import Observation

// turns an audio file into text
@MainActor
protocol RecordingTranscribing {
    func transcribe(_ audio: URL) async throws -> String
}

// reads a stretch of conversation (a few paragraphs, see `ConversationsViewModel.chunkCharacters`) and takes notes
@MainActor
protocol TranscriptAnalyzing {
    func notes(from transcript: String) async throws -> ConversationNotes
}

// the recordings the clip-on recorder uploaded: each is turned into text on the phone, then into notes.
// the text and notes are kept next to the audio, so a recording is only worked on once
@MainActor
@Observable
final class ConversationsViewModel {
    private(set) var entries: [RecordingEntry] = [] // newest first
    private(set) var isWorking = false
    private(set) var currentName: String?
    var errorMessage: String?

    // deleting the audio once it is text saves about 115 MB an hour, and can't be undone, so it starts off
    var deletesAudio: Bool {
        didSet { defaults.set(deletesAudio, forKey: Self.deleteKey) }
    }

    nonisolated static let chunkCharacters = 6000 // about 1,500 tokens, which fits Apple's model with room for the answer
    private static let deleteKey = "conversations.deleteAudio"

    private let directory: URL
    private let transcriber: any RecordingTranscribing
    private let analyzer: any TranscriptAnalyzing
    private let defaults: UserDefaults
    private var failed = Set<String>() // not tried again until the app is reopened, so one bad file doesn't loop

    init(directory: URL, transcriber: any RecordingTranscribing, analyzer: any TranscriptAnalyzing, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.defaults = defaults
        deletesAudio = defaults.bool(forKey: Self.deleteKey)
        entries = loadEntries()
        // empty ones saved before they were dropped on arrival
        entries.filter { $0.transcript.isBlank }.forEach(delete)
    }

    var pendingCount: Int { audioNames().subtracting(entries.map(\.name)).count + entries.filter(needsNotes).count }

    // works through everything not done yet, including recordings that arrive meanwhile. safe to call again at any time.
    // ones that failed are left alone until asked to try them again
    func processNew(retryingFailed: Bool = false) async {
        guard !isWorking else { return }
        if retryingFailed { failed.removeAll() }
        isWorking = true
        defer { isWorking = false; currentName = nil }
        while let name = nextAudio() {
            currentName = name
            do {
                try await transcribeAndNote(name)
            } catch {
                failed.insert(name)
                errorMessage = "Couldn't read \(name). \(error.localizedDescription)"
            }
        }
        // notes that failed earlier, like when the server was out of reach
        for entry in entries where needsNotes(entry) && !failed.contains(entry.name) {
            currentName = entry.name
            do {
                try save(RecordingEntry(name: entry.name, receivedAt: entry.receivedAt, transcript: entry.transcript, notes: try await takeNotes(entry.transcript)))
            } catch {
                failed.insert(entry.name)
                errorMessage = "Couldn't take notes on \(entry.name). \(error.localizedDescription)"
            }
        }
    }

    func delete(_ entry: RecordingEntry) {
        try? FileManager.default.removeItem(at: jsonURL(entry.name))
        try? FileManager.default.removeItem(at: audioURL(entry.name))
        entries.removeAll { $0.name == entry.name }
    }

    // MARK: - one recording

    private func transcribeAndNote(_ name: String) async throws {
        let audio = audioURL(name)
        // whole seconds, which is all the saved file keeps
        let created = (try? audio.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .now
        let received = Date(timeIntervalSince1970: created.timeIntervalSince1970.rounded(.down))
        let transcript = try await transcriber.transcribe(audio)
        // nobody was talking: there is nothing to keep, so the silent audio goes too, whatever the delete setting
        guard !transcript.isBlank else {
            try? FileManager.default.removeItem(at: audio)
            return
        }
        var entry = RecordingEntry(name: name, receivedAt: received, transcript: transcript, notes: nil)
        // the text is saved first: it took the longest, and shouldn't be lost if the notes can't be taken
        try save(entry)
        if deletesAudio { try? FileManager.default.removeItem(at: audio) }
        if entry.hasSpeech {
            do {
                entry.notes = try await takeNotes(transcript)
                try save(entry)
            } catch {
                failed.insert(name) // tried again once the app is reopened
                errorMessage = "Couldn't take notes on \(name). \(error.localizedDescription)"
            }
        }
    }

    private func takeNotes(_ transcript: String) async throws -> ConversationNotes {
        var parts: [ConversationNotes] = []
        for chunk in TranscriptChunker.chunks(transcript, maxCharacters: Self.chunkCharacters) {
            parts.append(try await analyzer.notes(from: chunk))
        }
        return .merge(parts)
    }

    private func needsNotes(_ entry: RecordingEntry) -> Bool { entry.hasSpeech && entry.notes == nil }

    // MARK: - files

    private func audioURL(_ name: String) -> URL { directory.appendingPathComponent(name + ".wav") }
    private func jsonURL(_ name: String) -> URL { directory.appendingPathComponent(name + ".json") }

    private func audioNames() -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(files.filter { $0.hasSuffix(".wav") }.map { String($0.dropLast(4)) })
    }

    // oldest first, so the conversations come out in the order they happened
    private func nextAudio() -> String? {
        audioNames().subtracting(entries.map(\.name)).subtracting(failed).sorted().first
    }

    private func loadEntries() -> [RecordingEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }
            .compactMap { try? decoder.decode(RecordingEntry.self, from: Data(contentsOf: directory.appendingPathComponent($0))) }
            .sorted(by: Self.newestFirst)
    }

    // recordings that arrived in the same second still have an order: their numbers
    private static func newestFirst(_ a: RecordingEntry, _ b: RecordingEntry) -> Bool {
        (a.receivedAt, a.name) > (b.receivedAt, b.name)
    }

    private func save(_ entry: RecordingEntry) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(to: jsonURL(entry.name), options: .atomic)
        if let index = entries.firstIndex(where: { $0.name == entry.name }) {
            entries[index] = entry
        } else {
            entries.append(entry)
            entries.sort(by: Self.newestFirst)
        }
    }
}

#if DEBUG
extension ConversationsViewModel {
    // for previews: no folder, and nothing that listens
    static var preview: ConversationsViewModel {
        struct Nothing: RecordingTranscribing, TranscriptAnalyzing {
            func transcribe(_ audio: URL) async throws -> String { "" }
            func notes(from transcript: String) async throws -> ConversationNotes { ConversationNotes(summary: "") }
        }
        return ConversationsViewModel(directory: URL.temporaryDirectory.appendingPathComponent("conversations-preview"),
                                      transcriber: Nothing(), analyzer: Nothing())
    }
}
#endif

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
