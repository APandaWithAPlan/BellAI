import Foundation
import Observation

@MainActor
@Observable
final class ServerConnectionMonitor {
    private(set) var isConnected = false
    private let session: URLSession
    private let fixedURL: URL?

    // no url means the chat server's address from Settings, looked up on every check
    init(session: URLSession = .shared, url: URL? = nil) {
        self.session = session
        self.fixedURL = url
    }

    func reset() {
        isConnected = false
    }

    func check() async {
        isConnected = false
        let url = fixedURL ?? HTTPBellAIService.baseURL.appendingPathComponent("api/version")
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
