import Foundation

// POST and GET /music/plays on the data server in /macserver/data
@MainActor
struct HTTPMusicLogService: MusicPlayLogging {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func record(_ plays: [SongPlay]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        _ = try await perform("POST", path: "music/plays", body: try encoder.encode(["plays": plays]))
    }

    func recentPlays(limit: Int) async throws -> [SongPlay] {
        let data = try await perform("GET", path: "music/plays?limit=\(limit)")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let reply = try? decoder.decode([String: [SongPlay]].self, from: data), let plays = reply["plays"] else {
            throw BellAIServiceError.invalidResponse
        }
        return plays
    }

    private func perform(_ method: String, path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "http://\(ServerSettings.address(.data))/\(path)") else { throw BellAIServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BellAIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw BellAIServiceError.http(http.statusCode) }
        return data
    }
}
