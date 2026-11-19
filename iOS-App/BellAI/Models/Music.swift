import Foundation

// one song the user played in Apple Music, as logged on the data server
nonisolated struct SongPlay: Codable, Equatable, Sendable {
    var songID: String
    var title: String
    var artist: String
    var genres: [String]
    var playedAt: Date

    enum CodingKeys: String, CodingKey {
        case songID = "song_id", title, artist, genres, playedAt = "played_at"
    }
}

// a song BellAI suggests, new to the user
nonisolated struct SuggestedSong: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
}

// what the logged plays say the user likes
nonisolated struct TasteProfile: Equatable, Sendable {
    let topArtists: [String]
    let topGenres: [String]
    let heardSongIDs: Set<String>

    var isEmpty: Bool { topArtists.isEmpty }

    init(plays: [SongPlay], limit: Int = 5) {
        topArtists = Self.top(plays.map(\.artist), limit: limit)
        // Apple tags nearly everything with the catch-all genre "Music", which says nothing about taste
        topGenres = Self.top(plays.flatMap(\.genres).filter { $0 != "Music" }, limit: limit)
        heardSongIDs = Set(plays.map(\.songID))
    }

    // most frequent first, ties by name so the same plays always give the same answer
    private static func top(_ names: [String], limit: Int) -> [String] {
        let counts = names.filter { !$0.isEmpty }.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(limit).map(\.key)
    }
}

// what the person is doing right now, as far as the phone can tell
nonisolated enum MotionKind: Sendable {
    case stationary, walking, running, cycling
}

// how energetic the music should be
nonisolated enum MusicIntensity: Int, CaseIterable, Comparable, Sendable {
    case calm, steady, energetic, intense

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .calm: "Calm"
        case .steady: "Steady"
        case .energetic: "Energetic"
        case .intense: "Intense"
        }
    }

    // added to a genre to find a playlist that fits
    var searchWords: String {
        switch self {
        case .calm: "chill relax"
        case .steady: "easy upbeat"
        case .energetic: "workout"
        case .intense: "high intensity workout"
        }
    }

    // heart rate as a share of its maximum: under 50% is resting, then easy, hard, and 80% or more is flat out
    init(heartRate: Double, maxHeartRate: Double) {
        switch heartRate / maxHeartRate {
        case ..<0.5: self = .calm
        case ..<0.65: self = .steady
        case ..<0.8: self = .energetic
        default: self = .intense
        }
    }

    init(motion: MotionKind) {
        switch motion {
        case .stationary: self = .calm
        case .walking: self = .steady
        case .running, .cycling: self = .energetic
        }
    }

    // heart rate and motion each give a level and the higher wins, so a heart rate that lags the first minutes
    // of a run doesn't drop the music, and a spike after stopping still gets music that matches it.
    // nil when the phone knows neither
    static func resolve(heartRate: Double?, maxHeartRate: Double, motion: MotionKind?) -> MusicIntensity? {
        let levels = [heartRate.map { Self(heartRate: $0, maxHeartRate: maxHeartRate) }, motion.map(Self.init(motion:))]
        return levels.compactMap { $0 }.max()
    }
}
