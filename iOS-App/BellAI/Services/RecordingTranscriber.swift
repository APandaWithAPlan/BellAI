import AVFoundation
import Foundation
import Speech

enum RecordingTranscriberError: LocalizedError {
    case needsNewerSystem, unsupportedLanguage

    var errorDescription: String? {
        switch self {
        case .needsNewerSystem: "Turning recordings into text on this phone needs iOS 26 or later."
        case .unsupportedLanguage: "Speech recognition on this phone doesn't support the current language."
        }
    }
}

// Apple's on-device speech model (SpeechAnalyzer), so the conversations never leave the phone
@MainActor
struct AppleRecordingTranscriber: RecordingTranscribing {
    func transcribe(_ audio: URL) async throws -> String {
        guard #available(iOS 26, *) else { throw RecordingTranscriberError.needsNewerSystem }
        return try await Self.transcribeOnDevice(audio)
    }

    @available(iOS 26, *)
    private static func transcribeOnDevice(_ audio: URL) async throws -> String {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw RecordingTranscriberError.unsupportedLanguage
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        // the language model downloads once, the first time it is needed
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()
        }
        // an hour is 115 MB, so it is read from the file as it goes, not loaded
        let file = try AVAudioFile(forReading: audio)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let text = transcriber.results.reduce(into: "") { $0 += String($1.text.characters) + " " }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
