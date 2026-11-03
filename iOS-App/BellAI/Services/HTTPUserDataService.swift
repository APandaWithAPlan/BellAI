import Foundation

// GET and PUT /data on the data server in /macserver/data
@MainActor
struct HTTPUserDataService: UserDataStore {
    private let fixedURL: URL?
    private let session: URLSession

    // no baseURL means the data server's address from Settings, looked up on use
    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.fixedURL = baseURL
        self.session = session
    }

    // host:port of the data server, from Settings, else DATA_SERVER_HOST in Info.plist, else ai-server:8001
    nonisolated static var configuredHost: String {
        ServerSettings.address(.data)
    }

    private var baseURL: URL {
        fixedURL ?? URL(string: "http://\(Self.configuredHost)")!
    }

    // nil if nothing saved yet
    func load() async throws -> [String: Any]? {
        let data = try await perform("GET")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json.keys.contains("data") else {
            throw BellAIServiceError.invalidResponse
        }
        return json["data"] as? [String: Any]
    }

    func save(_ data: [String: Any]) async throws {
        let body = ["data": data]
        guard JSONSerialization.isValidJSONObject(body) else { throw BellAIServiceError.invalidResponse }
        _ = try await perform("PUT", body: try JSONSerialization.data(withJSONObject: body))
    }

    private func perform(_ method: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "data"))
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
