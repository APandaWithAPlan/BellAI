import Foundation
import Observation

// Apple Music, through MusicKit in the app and a stub in the checks
@MainActor
protocol AppleMusicProviding {
    var isAuthorized: Bool { get }
    func requestAccess() async -> Bool
    // the songs played most recently, newest first
    func recentlyPlayed() async throws -> [SongPlay]
    // songs by artists like the ones played most, leaving out what was already heard
    func suggestions(for taste: TasteProfile) async throws -> [SuggestedSong]
    func createPlaylist(named name: String, from songs: [SuggestedSong]) async throws
    // starts a playlist that fits the intensity, in the genres played most
    func play(_ intensity: MusicIntensity, taste: TasteProfile) async throws
}

// where the songs the user played are kept
@MainActor
protocol MusicPlayLogging {
    func record(_ plays: [SongPlay]) async throws
    func recentPlays(limit: Int) async throws -> [SongPlay]
}

// how hard the person is working right now: heart rate from Apple Health, and what they are doing from the phone's motion
@MainActor
protocol WorkoutIntensityProviding {
    // asks for Health and motion access, once each. completion means the sheets were handled, not that access was granted
    func requestAccess() async
    // nil when neither heart rate nor motion is available
    func current() async -> MusicIntensity?
}

// learns from what the user plays in Apple Music, suggests new songs, and matches the music to their workout
@MainActor
@Observable
final class MusicViewModel {
    private(set) var isAuthorized: Bool
    private(set) var isBusy = false
    private(set) var suggestions: [SuggestedSong] = []
    private(set) var createdPlaylist: String?
    private(set) var followsWorkout = false
    private(set) var intensity: MusicIntensity? // what is playing now
    var errorMessage: String?

    private let music: any AppleMusicProviding
    private let log: any MusicPlayLogging
    private let workout: any WorkoutIntensityProviding
    private let defaults: UserDefaults
    private var isSyncing = false
    private var follow: Task<Void, Never>?
    private var pending: (level: MusicIntensity, ticks: Int)? // a new level waiting to prove it isn't a blip

    private static let lastSyncedKey = "music.lastSyncedSongID"
    private static let tasteSample = 1000
    private static let followInterval: Duration = .seconds(30)
    private static let ticksToSwitch = 2 // the same new level on two checks in a row, about a minute

    init(music: any AppleMusicProviding, log: any MusicPlayLogging, workout: any WorkoutIntensityProviding, defaults: UserDefaults = .standard) {
        self.music = music
        self.log = log
        self.workout = workout
        self.defaults = defaults
        isAuthorized = music.isAuthorized
    }

    func connect() async {
        isAuthorized = await music.requestAccess()
        if isAuthorized { await syncPlays() }
    }

    // logs what was played since the last time. Apple Music's history has no times, so the plays get the time they
    // were noticed, and its newest song is kept to know where the new ones end. the marker only moves once the server
    // has the plays, so a failed upload is simply tried again next time. quiet on failure: it runs without being asked
    func syncPlays() async {
        guard isAuthorized, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let recent = try await music.recentlyPlayed()
            guard let newest = recent.first else { return }
            let lastSynced = defaults.string(forKey: Self.lastSyncedKey)
            let fresh = recent.prefix { $0.songID != lastSynced }
            guard !fresh.isEmpty else { return }
            // one second apart, newest last, so the server keeps them in the order they were played
            let now = Date.now
            let stamped = fresh.reversed().enumerated().map { index, play in
                var play = play
                play.playedAt = now.addingTimeInterval(Double(index) - Double(fresh.count))
                return play
            }
            try await log.record(stamped)
            defaults.set(newest.songID, forKey: Self.lastSyncedKey)
        } catch {}
    }

    // works out new songs from everything logged so far
    func suggest() async {
        guard let taste = await taste() else { return }
        await work {
            suggestions = try await music.suggestions(for: taste)
            createdPlaylist = nil
        }
    }

    func createPlaylist() async {
        guard !suggestions.isEmpty else { return }
        let name = "BellAI Mix · \(Date.now.formatted(date: .abbreviated, time: .omitted))"
        await work {
            try await music.createPlaylist(named: name, from: suggestions)
            createdPlaylist = name
        }
    }

    // matches the music to the workout until turned off, or until the app leaves the screen
    func setFollowingWorkout(_ on: Bool) {
        follow?.cancel()
        follow = nil
        pending = nil
        followsWorkout = on
        guard on else { return }
        follow = Task {
            await workout.requestAccess()
            while !Task.isCancelled {
                await followTick()
                try? await Task.sleep(for: Self.followInterval)
            }
        }
    }

    func stopFollowing() {
        if followsWorkout { setFollowingWorkout(false) }
    }

    // one look at how hard the person is working. the music only changes once a new level has held for a couple of
    // looks in a row, so a quick spike doesn't flip the playlist
    func followTick() async {
        guard let level = await workout.current(), level != intensity else { pending = nil; return }
        let ticks = pending?.level == level ? (pending?.ticks ?? 0) + 1 : 1
        guard ticks >= Self.ticksToSwitch || intensity == nil else { pending = (level, ticks); return }
        pending = nil
        guard followsWorkout else { return }
        guard let taste = await taste() else { return stopFollowing() } // it has said why, and won't say it every 30 seconds
        do {
            try await music.play(level, taste: taste)
            intensity = level
        } catch {
            errorMessage = error.localizedDescription
            stopFollowing()
        }
    }

    // nil, with a message, if nothing was played yet or the server can't be reached
    private func taste() async -> TasteProfile? {
        do {
            let taste = TasteProfile(plays: try await log.recentPlays(limit: Self.tasteSample))
            if taste.isEmpty { errorMessage = "Play some music in Apple Music first, then BellAI can learn what you like." }
            return taste.isEmpty ? nil : taste
        } catch {
            errorMessage = "Couldn't read your listening history. \(error.localizedDescription)"
            return nil
        }
    }

    private func work(_ body: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await body() } catch { errorMessage = error.localizedDescription }
    }
}
