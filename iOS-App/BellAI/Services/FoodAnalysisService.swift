import Foundation

@MainActor
protocol FoodAnalysisService {
    /// A one sentence summary written to be read aloud. Needs a photo, a note, or both.
    func analyze(jpeg: Data?, note: String?) async throws -> String
    /// wav audio of `text`
    func speak(_ text: String) async throws -> Data
}

// POST /analyze and /speak on the voice server, same host as the websocket
@MainActor
struct HTTPFoodAnalysisService: FoodAnalysisService {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://\(WebSocketVoiceService.configuredHost)")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func analyze(jpeg: Data?, note: String?) async throws -> String {
        let boundary = "bellai-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "analyze"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60 // a cold start takes about 10 s
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        if let jpeg {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
            body.append(jpeg)
            append("\r\n")
        }
        if let note {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"text\"\r\n\r\n\(note)\r\n")
        }
        append("--\(boundary)--\r\n")
        request.httpBody = body

        let data = try await perform(request)
        guard let result = try? JSONDecoder().decode(AnalysisResponse.self, from: data),
              !result.summary.isEmpty else {
            throw BellAIServiceError.invalidResponse
        }
        return result.summary
    }

    func speak(_ text: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "speak"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["text": text])
        let wav = try await perform(request)
        guard !wav.isEmpty else { throw BellAIServiceError.invalidResponse }
        return wav
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BellAIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // errors come back as {"detail": "..."}
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
            switch http.statusCode {
            case 413: throw BellAIServiceError.server(413, "That photo is too large (10 MB max).")
            case _ where detail?.isEmpty == false: throw BellAIServiceError.server(http.statusCode, String(detail!.prefix(1_000)))
            default: throw BellAIServiceError.http(http.statusCode)
            }
        }
        return data
    }
}

private struct AnalysisResponse: Decodable {
    let summary: String
}

private struct ErrorResponse: Decodable {
    let detail: String
}
