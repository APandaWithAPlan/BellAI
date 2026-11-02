import Foundation
import Observation

@MainActor
@Observable
final class ServerConnectionMonitor {
    private(set) var isConnected = false
    private let session: URLSession
    private let url: URL

    init(session: URLSession = .shared,
         url: URL = HTTPBellAIService.baseURL.appendingPathComponent("api/version")) {
        self.session = session
        self.url = url
    }

    func reset() {
        isConnected = false
    }

    func check() async {
        isConnected = false
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let health = try? JSONDecoder().decode(Health.self, from: data) else { return }
            isConnected = !health.version.isEmpty
        } catch {
            isConnected = false
        }
    }

    private struct Health: Decodable {
        let version: String
    }
}
