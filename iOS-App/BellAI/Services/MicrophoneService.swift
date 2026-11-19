import AVFoundation
import Foundation

@MainActor
protocol MicrophoneListening: AnyObject {
    /// Records until the speaker pauses, `finish()` is called or `cancel()` stops it. Returns what was said, nil if nothing was.
    /// `onTranscribing` is called when the recording ends and the server is turning it into text.
    func listen(onReady: @escaping @MainActor () -> Void, onTranscribing: @escaping @MainActor () -> Void) async throws -> String?
    /// Ends the recording now and goes on to transcribe what was heard
    func finish()
    func cancel()
}

/// One utterance per tap. It records on the phone and the Mac's Whisper turns it into text, so nothing goes to Apple.
@MainActor
final class MicrophoneService: MicrophoneListening {
    private let engine = AVAudioEngine()
    private let transcriber: any SpeechTranscribing
    private var sessionID: UUID?
    private var finishRequested = false
    private var tapInstalled = false
    private var sessionActive = false

    init(transcriber: (any SpeechTranscribing)? = nil) {
        self.transcriber = transcriber ?? HTTPSpeechTranscriber()
    }

    func listen(onReady: @escaping @MainActor () -> Void, onTranscribing: @escaping @MainActor () -> Void) async throws -> String? {
        cancel()
        let id = UUID()
        sessionID = id
        finishRequested = false
        defer {
            stopRecording()
            if sessionID == id { sessionID = nil }
        }
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        try checkSession(id)
        guard allowed else {
            throw MicrophoneError.unavailable("Allow Microphone access for BellAI in Settings to use voice input.")
        }
        let capture = try startRecording()
        onReady()

        var endpoint = SpeechEndpoint()
        while !finishRequested {
            try await Task.sleep(for: .milliseconds(100))
            try checkSession(id)
            if endpoint.hear(level: capture.takeLoudness(), seconds: 0.1) { break }
        }
        stopRecording()
        onTranscribing()
        let text = try await transcriber.transcribe(capture.wav)
        try checkSession(id)
        return text.isEmpty ? nil : text
    }

    func finish() {
        if sessionID != nil { finishRequested = true }
    }

    func cancel() {
        sessionID = nil
        stopRecording()
    }

    private func checkSession(_ id: UUID) throws {
        try Task.checkCancellation()
        guard sessionID == id else { throw CancellationError() }
    }

    private func startRecording() throws -> AudioCapture {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)
        sessionActive = true
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, let capture = AudioCapture(input: format) else {
            throw MicrophoneError.unavailable("No microphone is available.")
        }
        Self.installAudioTap(input, format: format, capture: capture)
        tapInstalled = true
        engine.prepare()
        try engine.start()
        return capture
    }

    // safe to call again, it only undoes what is still on
    private func stopRecording() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        #if os(iOS)
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
        sessionActive = false
    }

    // Audio callbacks run on an audio thread, outside MainActor isolation.
    nonisolated private static func installAudioTap(_ input: AVAudioInputNode, format: AVAudioFormat, capture: AudioCapture) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            capture.append(buffer)
        }
    }
}

/// Decides when the speaker is done, from the loudness of each short slice of audio.
nonisolated struct SpeechEndpoint {
    static let speechLevel: Float = 0.02 // loudness (RMS, 0 to 1) that counts as someone talking
    static let pauseToFinish = 1.4 // seconds of quiet after talking that ends it
    static let waitForSpeech = 8.0 // seconds of quiet before any talking that ends it too, it is still sent in case it was only soft
    static let longest = 60.0

    private var elapsed = 0.0
    private var quiet = 0.0
    private(set) var heardSpeech = false

    // true once the recording should stop
    mutating func hear(level: Float, seconds: Double) -> Bool {
        elapsed += seconds
        if level >= Self.speechLevel {
            heardSpeech = true
            quiet = 0
        } else {
            quiet += seconds
        }
        return elapsed >= Self.longest || quiet >= (heardSpeech ? Self.pauseToFinish : Self.waitForSpeech)
    }
}

/// What the microphone heard as 16 kHz mono 16 bit audio, which is what the server's Whisper wants.
/// The tap fills it on the audio thread while the main thread reads how loud it is.
nonisolated final class AudioCapture: @unchecked Sendable {
    static let sampleRate = 16_000.0

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private var pcm = Data()
    private var loudest: Float = 0

    init?(input: AVAudioFormat) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: input, to: format) else { return nil }
        self.format = format
        self.converter = converter
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * Self.sampleRate / buffer.format.sampleRate) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        let supplied = Flag()
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied.isSet {
                status.pointee = .noDataNow
                return nil
            }
            supplied.isSet = true
            status.pointee = .haveData
            return buffer
        }
        let count = Int(converted.frameLength)
        guard error == nil, count > 0, let samples = converted.int16ChannelData?[0] else { return }
        var sum: Float = 0
        for index in 0..<count {
            let sample = Float(samples[index]) / 32768
            sum += sample * sample
        }
        append(UnsafeBufferPointer(start: samples, count: count), level: (sum / Float(count)).squareRoot())
    }

    // for the checks, which have no microphone
    func append(_ samples: UnsafeBufferPointer<Int16>, level: Float) {
        lock.lock()
        pcm.append(samples)
        loudest = max(loudest, level)
        lock.unlock()
    }

    /// the loudest slice since this was last asked
    func takeLoudness() -> Float {
        lock.lock()
        defer { lock.unlock() }
        let level = loudest
        loudest = 0
        return level
    }

    var wav: Data {
        lock.lock()
        let body = pcm
        lock.unlock()
        var header = Data("RIFF".utf8)
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        put(UInt32(36 + body.count))
        header.append(Data("WAVEfmt ".utf8))
        put(UInt32(16)) // size of the format part
        put(UInt16(1)) // plain pcm
        put(UInt16(1)) // mono
        put(UInt32(Self.sampleRate))
        put(UInt32(Self.sampleRate) * 2) // bytes per second
        put(UInt16(2)) // bytes per frame
        put(UInt16(16)) // bits
        header.append(Data("data".utf8))
        put(UInt32(body.count))
        return header + body
    }

    private final class Flag: @unchecked Sendable {
        var isSet = false
    }
}

private enum MicrophoneError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): message }
    }
}
