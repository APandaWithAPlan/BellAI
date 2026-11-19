import Foundation

@MainActor
protocol CaptureService {
    /// newest first, with how many there are in all
    func captures(limit: Int) async throws -> (captures: [Capture], total: Int)
    /// where the clip can be played from, which supports seeking
    func videoURL(for capture: Capture) -> URL
    func thumbnailURL(for capture: Capture) -> URL
}

// GET /captures on the data server, where the camera's earlier clips are listed and streamed from
@MainActor
struct HTTPCaptureService: CaptureService {
    private let fixedURL: URL?
    private let session: URLSession

    // no baseURL means the data server's address from Settings, looked up on use
    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.fixedURL = baseURL
        self.session = session
    }

    private var baseURL: URL {
        fixedURL ?? URL(string: "http://\(HTTPUserDataService.configuredHost)")!
    }

    func captures(limit: Int) async throws -> (captures: [Capture], total: Int) {
        var components = URLComponents(url: baseURL.appending(path: "captures"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20 // the Mac looks at the drive before it answers
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BellAIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // errors come back as {"detail": "..."}
            let detail = (try? JSONDecoder().decode(ErrorReply.self, from: data))?.detail
            if let detail, !detail.isEmpty { throw BellAIServiceError.server(http.statusCode, String(detail.prefix(500))) }
            throw BellAIServiceError.http(http.statusCode)
        }
        guard let list = try? JSONDecoder().decode(CaptureList.self, from: data) else { throw BellAIServiceError.invalidResponse }
        return (list.captures, list.total)
    }

    func videoURL(for capture: Capture) -> URL {
        baseURL.appending(path: "captures").appending(path: capture.id).appending(path: "video")
    }

    func thumbnailURL(for capture: Capture) -> URL {
        baseURL.appending(path: "captures").appending(path: capture.id).appending(path: "thumbnail")
    }

    private struct CaptureList: Decodable {
        let captures: [Capture]
        let total: Int
    }

    private struct ErrorReply: Decodable { let detail: String }
}
