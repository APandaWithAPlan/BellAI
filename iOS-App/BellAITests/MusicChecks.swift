import Foundation

@MainActor
private final class StubMusic: AppleMusicProviding {
    var isAuthorized = true
    var recent: [SongPlay] = []
    var played: [MusicIntensity] = []
    var suggested: [SuggestedSong] = [SuggestedSong(id: "n1", title: "New", artist: "Someone")]
    func requestAccess() async -> Bool { isAuthorized }
    func recentlyPlayed() async throws -> [SongPlay] { recent }
    func suggestions(for taste: TasteProfile) async throws -> [SuggestedSong] { suggested }
    func createPlaylist(named name: String, from songs: [SuggestedSong]) async throws {}
    func play(_ intensity: MusicIntensity, taste: TasteProfile) async throws { played.append(intensity) }
}

@MainActor
private final class StubLog: MusicPlayLogging {
    var stored: [SongPlay] = []
    var batches: [[SongPlay]] = []
    var fails = false
    func record(_ plays: [SongPlay]) async throws {
        if fails { throw URLError(.notConnectedToInternet) }
        batches.append(plays)
        stored += plays
    }
    func recentPlays(limit: Int) async throws -> [SongPlay] { stored }
}

@MainActor
private final class StubWorkout: WorkoutIntensityProviding {
    var level: MusicIntensity?
    func requestAccess() async {}
    func current() async -> MusicIntensity? { level }
}

private func song(_ id: String, artist: String = "A", genres: [String] = ["Pop"]) -> SongPlay {
    SongPlay(songID: id, title: "Song \(id)", artist: artist, genres: genres, playedAt: .now)
}

@main
struct MusicChecks {
    @MainActor
    static func main() async throws {
        // taste: most played first, ties by name, and the catch-all "Music" genre says nothing
        let taste = TasteProfile(plays: [
            song("1", artist: "B", genres: ["Music", "Rock"]), song("2", artist: "A", genres: ["Music", "Pop"]),
            song("3", artist: "B", genres: ["Music", "Pop"]), song("4", artist: "C", genres: ["Music", "Pop"]),
        ])
        precondition(taste.topArtists == ["B", "A", "C"])
        precondition(taste.topGenres == ["Pop", "Rock"])
        precondition(taste.heardSongIDs == ["1", "2", "3", "4"])
        precondition(TasteProfile(plays: []).isEmpty)

        // intensity from heart rate (max 190), motion, and both
        precondition(MusicIntensity(heartRate: 80, maxHeartRate: 190) == .calm)
        precondition(MusicIntensity(heartRate: 100, maxHeartRate: 190) == .steady)
        precondition(MusicIntensity(heartRate: 130, maxHeartRate: 190) == .energetic)
        precondition(MusicIntensity(heartRate: 160, maxHeartRate: 190) == .intense)
        precondition(MusicIntensity.resolve(heartRate: nil, maxHeartRate: 190, motion: nil) == nil)
        precondition(MusicIntensity.resolve(heartRate: nil, maxHeartRate: 190, motion: .walking) == .steady)
        precondition(MusicIntensity.resolve(heartRate: 80, maxHeartRate: 190, motion: .running) == .energetic) // heart rate lags
        precondition(MusicIntensity.resolve(heartRate: 165, maxHeartRate: 190, motion: .stationary) == .intense) // just stopped

        // logging: first sync sends everything oldest first, later syncs only what is new, a failed upload is retried
        let defaults = UserDefaults(suiteName: "bellai.music.checks")!
        defaults.removePersistentDomain(forName: "bellai.music.checks")
        let music = StubMusic(), log = StubLog(), workout = StubWorkout()
        let model = MusicViewModel(music: music, log: log, workout: workout, defaults: defaults)
        music.recent = [song("3"), song("2"), song("1")]
        log.fails = true
        await model.syncPlays()
        precondition(log.batches.isEmpty && defaults.string(forKey: "music.lastSyncedSongID") == nil)
        log.fails = false
        await model.syncPlays()
        precondition(log.batches.count == 1 && log.stored.map(\.songID) == ["1", "2", "3"])
        precondition(log.stored[0].playedAt < log.stored[2].playedAt && log.stored[2].playedAt <= .now)
        await model.syncPlays()
        precondition(log.batches.count == 1) // nothing new
        music.recent = [song("5"), song("4"), song("3"), song("2")]
        await model.syncPlays()
        precondition(log.batches.count == 2 && log.batches[1].map(\.songID) == ["4", "5"])

        // not connected: nothing is logged, and nothing is asked of Apple Music
        let locked = StubMusic()
        locked.isAuthorized = false
        let lockedModel = MusicViewModel(music: locked, log: StubLog(), workout: workout, defaults: defaults)
        precondition(!lockedModel.isAuthorized)
        await lockedModel.syncPlays()

        // suggestions come from the log, and say so when there is nothing to learn from yet
        let empty = MusicViewModel(music: music, log: StubLog(), workout: workout, defaults: defaults)
        await empty.suggest()
        precondition(empty.suggestions.isEmpty && empty.errorMessage?.contains("Play some music") == true)
        await model.suggest()
        precondition(model.suggestions.map(\.id) == ["n1"] && model.errorMessage == nil)
        await model.createPlaylist()
        precondition(model.createdPlaylist?.hasPrefix("BellAI Mix") == true)

        // following the workout: plays at once the first time, then a new level has to hold for two looks in a row
        model.setFollowingWorkout(true)
        try await Task.sleep(for: .milliseconds(200)) // the loop's first look, with no level known yet
        precondition(music.played.isEmpty && model.intensity == nil)
        workout.level = .steady
        await model.followTick()
        precondition(music.played == [.steady] && model.intensity == .steady)
        workout.level = .intense
        await model.followTick()
        precondition(music.played == [.steady]) // one look isn't enough
        workout.level = .steady
        await model.followTick()
        workout.level = .intense
        await model.followTick()
        precondition(music.played == [.steady]) // the blip reset the count
        await model.followTick()
        precondition(music.played == [.steady, .intense] && model.intensity == .intense)
        model.stopFollowing()
        precondition(!model.followsWorkout)

        print("music checks passed")
    }
}
