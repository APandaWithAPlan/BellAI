import Foundation
import MusicKit

// needs the MusicKit service switched on for the app's ID in the Apple developer account
enum AppleMusicError: LocalizedError {
    case notAuthorized, noSubscription, nothingFound, playlistsUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Allow BellAI to use Apple Music in Settings."
        case .noSubscription: "Playing music needs an Apple Music subscription."
        case .nothingFound: "I couldn't find anything new yet. Play more music and try again."
        case .playlistsUnavailable: "Playlists can only be created on iPhone and iPad."
        }
    }
}

struct AppleMusicService: AppleMusicProviding {
    private static let recentLimit = 30
    private static let suggestionLimit = 20

    var isAuthorized: Bool { MusicAuthorization.currentStatus == .authorized }

    func requestAccess() async -> Bool {
        await MusicAuthorization.request() == .authorized
    }

    func recentlyPlayed() async throws -> [SongPlay] {
        guard isAuthorized else { throw AppleMusicError.notAuthorized }
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = Self.recentLimit
        return try await request.response().items.map {
            SongPlay(songID: $0.id.rawValue, title: $0.title, artist: $0.artistName, genres: $0.genreNames, playedAt: .now)
        }
    }

    func suggestions(for taste: TasteProfile) async throws -> [SuggestedSong] {
        guard isAuthorized else { throw AppleMusicError.notAuthorized }
        let known = Set(taste.topArtists)
        var found: [SuggestedSong] = []
        for name in taste.topArtists.prefix(3) {
            var search = MusicCatalogSearchRequest(term: name, types: [Artist.self])
            search.limit = 1
            guard let artist = try await search.response().artists.first,
                  let similar = try await artist.with([.similarArtists]).similarArtists else { continue }
            for other in similar.prefix(2) where !known.contains(other.name) {
                let top = try await other.with([.topSongs]).topSongs ?? []
                for song in top.prefix(3) where !taste.heardSongIDs.contains(song.id.rawValue)
                    && !found.contains(where: { $0.id == song.id.rawValue }) {
                    found.append(SuggestedSong(id: song.id.rawValue, title: song.title, artist: song.artistName))
                }
            }
        }
        guard !found.isEmpty else { throw AppleMusicError.nothingFound }
        return Array(found.prefix(Self.suggestionLimit))
    }

    func createPlaylist(named name: String, from songs: [SuggestedSong]) async throws {
        guard isAuthorized else { throw AppleMusicError.notAuthorized }
        #if os(iOS)
        let ids = songs.map { MusicItemID($0.id) }
        let catalog = try await MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids).response().items
        // the catalog answers in its own order, so put the songs back in the order they were suggested
        let ordered = ids.compactMap { id in catalog.first { $0.id == id } }
        guard !ordered.isEmpty else { throw AppleMusicError.nothingFound }
        _ = try await MusicLibrary.shared.createPlaylist(name: name, description: "Suggested by BellAI", items: ordered)
        #else
        throw AppleMusicError.playlistsUnavailable
        #endif
    }

    func play(_ intensity: MusicIntensity, taste: TasteProfile) async throws {
        guard isAuthorized else { throw AppleMusicError.notAuthorized }
        guard try await MusicSubscription.current.canPlayCatalogContent else { throw AppleMusicError.noSubscription }
        let term = [taste.topGenres.first, intensity.searchWords].compactMap { $0 }.joined(separator: " ")
        var search = MusicCatalogSearchRequest(term: term, types: [Playlist.self])
        search.limit = 1
        guard let playlist = try await search.response().playlists.first else { throw AppleMusicError.nothingFound }
        let player = ApplicationMusicPlayer.shared
        player.queue = [playlist]
        try await player.play()
    }
}
