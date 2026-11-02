import AVFoundation
import Foundation
import Speech

@MainActor
protocol MicrophoneListening: AnyObject {
    func listen(onReady: @escaping @MainActor () -> Void) async throws -> String?
    func cancel()
}

/// One utterance per tap. Recognition activity resets the five-second silence deadline.
@MainActor
final class MicrophoneService: MicrophoneListening {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var completion: CheckedContinuation<String?, Error>?
    private var timeout: Task<Void, Never>?
    private var sessionID: UUID?
    private var transcript = ""
    private var tapInstalled = false
    private var sessionActive = false

    func listen(onReady: @escaping @MainActor () -> Void) async throws -> String? {
        cancel()
        let id = UUID()
        sessionID = id
        do {
            let permission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            try checkSession(id)
            guard permission == .authorized else {
                throw MicrophoneError.unavailable("Allow Speech Recognition for BellAI in Settings to use voice input.")
            }
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            try checkSession(id)
            guard allowed else {
                throw MicrophoneError.unavailable("Allow Microphone access for BellAI in Settings to use voice input.")
            }
            guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
                throw MicrophoneError.unavailable("Speech recognition is unavailable. Please try again later.")
            }
            self.recognizer = recognizer
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
            sessionActive = true
            #endif
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw MicrophoneError.unavailable("No microphone is available.")
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            transcript = ""
            return try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.bestTranscription.formattedString
                    let isFinal = result?.isFinal ?? false
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id else { return }
                        if let text, text != self.transcript {
                            self.transcript = text
                            self.resetTimeout(id)
                        }
                        if isFinal {
                            self.finish(.success(self.transcript))
                        } else if let error {
                            let failure = error as NSError
                            print("[Microphone] Speech error: \(failure.domain) (\(failure.code)), locale: \(self.recognizer?.locale.identifier ?? "unknown")")
                            if failure.domain == "kAFAssistantErrorDomain", failure.code == 1110 {
                                self.finish(.success(""))
                            } else {
                                self.finish(.failure(Self.recognitionError(failure)))
                            }
                        }
                    }
                }
                Self.installAudioTap(input, format: format, request: request)
                tapInstalled = true
                do {
                    engine.prepare()
                    try engine.start()
                    onReady()
                    resetTimeout(id)
                } catch {
                    finish(.failure(error))
                }
            }
        } catch {
            if sessionID == id { cancel() }
            throw error
        }
    }

    // Audio callbacks run on an audio thread, outside MainActor isolation.
    nonisolated private static func installAudioTap(_ input: AVAudioInputNode, format: AVAudioFormat,
                                                    request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func checkSession(_ id: UUID) throws {
        try Task.checkCancellation()
        guard sessionID == id else { throw CancellationError() }
    }

    private func resetTimeout(_ id: UUID) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.sessionID == id else { return }
            self.finish(.success(self.transcript))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        sessionID = nil
        timeout?.cancel()
        timeout = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        recognizer = nil
        request = nil
        #if os(iOS)
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
        sessionActive = false
        let continuation = completion
        completion = nil
        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            continuation?.resume(returning: trimmed.isEmpty ? nil : trimmed)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    static func recognitionError(_ error: NSError) -> Error {
        guard error.domain == "kLSRErrorDomain" else { return error }
        switch error.code {
        case 102:
            return MicrophoneError.unavailable("Speech recognition language files are not installed. Enable Dictation for your language in Settings, then try again. (Speech error 102)")
        case 201:
            return MicrophoneError.unavailable("Siri or Dictation is disabled. Enable Dictation in Settings, then try again. (Speech error 201)")
        case 300:
            #if targetEnvironment(simulator)
            return MicrophoneError.unavailable("Apple’s speech recognizer could not start in this Simulator. Try voice input on a physical iPhone and check that Dictation works there. (Speech error 300)")
            #else
            return MicrophoneError.unavailable("Apple’s speech recognizer could not start. Check that keyboard Dictation works for your language, check your internet connection, then try again. (Speech error 300)")
            #endif
        default:
            return error
        }
    }
}

private enum MicrophoneError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): message }
    }
}
