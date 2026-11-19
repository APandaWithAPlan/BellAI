import Foundation

@MainActor
private final class StubTranscriber: RecordingTranscribing {
    var texts: [String: String] = [:] // by file name
    var failing: Set<String> = []
    var calls: [String] = []
    func transcribe(_ audio: URL) async throws -> String {
        calls.append(audio.lastPathComponent)
        if failing.contains(audio.lastPathComponent) { throw URLError(.cannotDecodeContentData) }
        return texts[audio.lastPathComponent] ?? ""
    }
}

@MainActor
private final class StubAnalyzer: TranscriptAnalyzing {
    var fails = false
    var seen: [String] = []
    func notes(from transcript: String) async throws -> ConversationNotes {
        if fails { throw URLError(.notConnectedToInternet) }
        seen.append(transcript)
        return ConversationNotes(summary: "S\(seen.count).", actionItems: ["Call Sam"], topics: ["Plans"], people: ["Sam"], comment: "Nice.")
    }
}

private let talk = "We should book the dentist on Friday. Sam said he will send the invoice tomorrow."

@main
struct ConversationsChecks {
    @MainActor
    static func main() async throws {
        // chunking: nothing lost, nothing over the limit, cut after sentences where possible
        let sentences = (1...40).map { "This is sentence number \($0)." }.joined(separator: " ")
        let chunks = TranscriptChunker.chunks(sentences, maxCharacters: 200)
        precondition(chunks.count > 1 && chunks.allSatisfy { $0.count <= 200 && $0.hasSuffix(".") })
        precondition(chunks.joined(separator: " ") == sentences)
        precondition(TranscriptChunker.chunks("short", maxCharacters: 200) == ["short"])
        precondition(TranscriptChunker.chunks("   ", maxCharacters: 200).isEmpty)
        let unbroken = String(repeating: "a", count: 450)
        precondition(TranscriptChunker.chunks(unbroken, maxCharacters: 200).map(\.count) == [200, 200, 50])

        // merging: summaries in order, each item once
        let merged = ConversationNotes.merge([
            ConversationNotes(summary: "One.", actionItems: ["Call Sam", " "], topics: ["Plans"], people: ["Sam"], comment: "A"),
            ConversationNotes(summary: "Two.", actionItems: ["call sam", "Pay rent"], topics: ["Money"], people: ["Sam", "Ana"], comment: ""),
        ])
        precondition(merged.summary == "One. Two." && merged.actionItems == ["Call Sam", "Pay rent"])
        precondition(merged.topics == ["Plans", "Money"] && merged.people == ["Sam", "Ana"] && merged.comment == "A")

        // a model that leaves fields out still decodes
        let partial = try JSONDecoder().decode(ConversationNotes.self, from: Data(#"{"summary":"Hi"}"#.utf8))
        precondition(partial == ConversationNotes(summary: "Hi"))

        // the pipeline
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("conversations-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "conversations-checks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for name in ["rec_000002", "rec_000001", "rec_000003", "rec_000004"] {
            try Data("audio".utf8).write(to: directory.appendingPathComponent(name + ".wav"))
        }
        try Data("half".utf8).write(to: directory.appendingPathComponent("rec_000005.wav.part")) // an upload in progress isn't audio yet

        let transcriber = StubTranscriber(), analyzer = StubAnalyzer()
        transcriber.texts = ["rec_000001.wav": talk, "rec_000002.wav": "hmm", "rec_000003.wav": talk]
        transcriber.failing = ["rec_000004.wav"]
        let model = ConversationsViewModel(directory: directory, transcriber: transcriber, analyzer: analyzer, defaults: defaults)
        precondition(model.entries.isEmpty && model.pendingCount == 4 && !model.deletesAudio)

        await model.processNew()
        precondition(transcriber.calls == ["rec_000001.wav", "rec_000002.wav", "rec_000003.wav", "rec_000004.wav"]) // in order, once each
        precondition(model.entries.count == 3 && !model.isWorking)
        let first = model.entries.first { $0.name == "rec_000001" }!
        precondition(first.transcript == talk && first.notes?.summary == "S1." && first.hasSpeech)
        let stray = model.entries.first { $0.name == "rec_000002" }!
        precondition(!stray.hasSpeech && stray.notes == nil) // too little said to take notes on
        precondition(analyzer.seen.count == 2)
        precondition(model.errorMessage?.contains("rec_000004") == true) // the bad file is reported, the rest still done
        model.errorMessage = nil
        precondition(FileManager.default.fileExists(atPath: directory.appendingPathComponent("rec_000001.wav").path)) // audio kept by default

        // nothing is done twice, and a new run, like after reopening the app, reads the saved text instead
        await model.processNew()
        precondition(transcriber.calls.count == 4)
        let reopened = ConversationsViewModel(directory: directory, transcriber: transcriber, analyzer: analyzer, defaults: defaults)
        precondition(reopened.entries.map(\.name) == model.entries.map(\.name) && reopened.entries.first { $0.name == "rec_000001" } == first)
        precondition(reopened.pendingCount == 1) // only the one that failed

        // the text is kept when notes fail, and the notes are taken later without listening again
        let phone = directory.appendingPathComponent("rec_000006.wav")
        try Data("audio".utf8).write(to: phone)
        transcriber.texts["rec_000006.wav"] = talk
        analyzer.fails = true
        await model.processNew()
        let waiting = model.entries.first { $0.name == "rec_000006" }!
        precondition(waiting.transcript == talk && waiting.notes == nil && model.errorMessage?.contains("take notes") == true)
        let calls = transcriber.calls.count
        analyzer.fails = false
        let retry = ConversationsViewModel(directory: directory, transcriber: transcriber, analyzer: analyzer, defaults: defaults)
        await retry.processNew()
        precondition(retry.entries.first { $0.name == "rec_000006" }?.notes != nil)
        precondition(transcriber.calls.count == calls + 1) // only rec_000004 was tried again, which fails again

        // a silent recording leaves nothing behind, audio included, even with the audio kept
        let silent = directory.appendingPathComponent("rec_000008.wav")
        try Data("audio".utf8).write(to: silent)
        transcriber.texts["rec_000008.wav"] = "  \n "
        await model.processNew()
        precondition(!model.entries.contains { $0.name == "rec_000008" } && !FileManager.default.fileExists(atPath: silent.path))
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("rec_000008.json").path))
        let calls8 = transcriber.calls.count
        await model.processNew()
        precondition(transcriber.calls.count == calls8) // and isn't heard again

        // empty ones already saved are cleared when the app opens
        let old = RecordingEntry(name: "rec_000009", receivedAt: .now, transcript: "", notes: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(old).write(to: directory.appendingPathComponent("rec_000009.json"))
        try Data("audio".utf8).write(to: directory.appendingPathComponent("rec_000009.wav"))
        let cleaned = ConversationsViewModel(directory: directory, transcriber: transcriber, analyzer: analyzer, defaults: defaults)
        precondition(!cleaned.entries.contains { $0.name == "rec_000009" })
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("rec_000009.json").path))
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("rec_000009.wav").path))

        // asking again tries the failed file again, and it works this time
        transcriber.failing = []
        transcriber.texts["rec_000004.wav"] = talk
        await model.processNew()
        precondition(!model.entries.contains { $0.name == "rec_000004" }) // not without being asked
        await model.processNew(retryingFailed: true)
        precondition(model.entries.first { $0.name == "rec_000004" }?.notes != nil)

        // deleting the audio once it is text, when asked
        model.deletesAudio = true
        let doomed = directory.appendingPathComponent("rec_000007.wav")
        try Data("audio".utf8).write(to: doomed)
        transcriber.texts["rec_000007.wav"] = talk
        await model.processNew()
        precondition(!FileManager.default.fileExists(atPath: doomed.path) && model.entries.contains { $0.name == "rec_000007" && $0.notes != nil })
        precondition(ConversationsViewModel(directory: directory, transcriber: transcriber, analyzer: analyzer, defaults: defaults).deletesAudio)

        // deleting a conversation removes its text and its audio
        model.delete(first)
        precondition(!model.entries.contains(first) && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("rec_000001.json").path))
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("rec_000001.wav").path))

        print("conversations checks passed")
    }
}
