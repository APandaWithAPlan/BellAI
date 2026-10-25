import AVFoundation
import Foundation
import Observation

@MainActor
protocol SpeechPlaying: AnyObject {
    var isSpeaking: Bool { get }
    func enqueue(_ wav: Data) // plays now, or after whatever is already playing
    func stop() // also clears the queue
    func stopForRecording() async
}

extension SpeechPlaying {
    func stopForRecording() async { stop() }
}

// plays the sentence clips one after another
@MainActor
@Observable
final class SpeechPlayer: SpeechPlaying {
    private(set) var isSpeaking = false

    @ObservationIgnored private var queue: [Data] = []
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    // serial, so start/end happen in order and never on the main thread
    private let sessionQueue = DispatchQueue(label: "BellAI.audio-session")

    func enqueue(_ wav: Data) {
        queue.append(wav)
        guard playbackTask == nil else { return }
        isSpeaking = true
        playbackTask = Task { await playQueue() }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        queue.removeAll()
        player?.stop()
        player = nil
        isSpeaking = false
        endSession()
    }

    func stopForRecording() async {
        stop()
        // Drain playback-session cleanup before recording takes over.
        await withCheckedContinuation { continuation in
            sessionQueue.async { continuation.resume() }
        }
    }

    private func playQueue() async {
        await startSession()
        while !Task.isCancelled, !queue.isEmpty {
            let wav = queue.removeFirst()
            guard let clip = try? AVAudioPlayer(data: wav) else { continue }
            player = clip
            guard clip.play() else { continue }
            while clip.isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        guard !Task.isCancelled else { return } // stop() already cleaned up
        player = nil
        playbackTask = nil
        isSpeaking = false
        endSession()
    }

    // AVAudioSession is iOS only, the mac check script compiles this file too
    private func startSession() async {
        #if os(iOS)
        await withCheckedContinuation { done in
            sessionQueue.async {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .spokenAudio)
                try? session.setActive(true)
                done.resume()
            }
        }
        #endif
    }

    private func endSession() {
        #if os(iOS)
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }
}
