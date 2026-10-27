import Foundation

@MainActor
protocol BellAIService {
    func send(_ request: ChatRequest) async throws -> ChatResponse
}

enum BellAIServiceError: LocalizedError {
    case invalidResponse
    case http(Int)
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .server(let code, let message):
            "The AI server request failed (HTTP \(code)): \(message)"
        case .invalidResponse:
            "The AI server returned an invalid or incomplete response. Please try again."
        case .http(401), .http(403):
            "The AI server rejected the request. Check your server permissions and model access."
        case .http(429):
            "The AI server's usage limit was reached. Please try again later."
        case .http(let code):
            "The AI server request failed (HTTP \(code)). Please try again."
        }
    }
}

@MainActor
struct HTTPBellAIService: BellAIService {
    nonisolated static let baseURL = URL(string: "http://ai-server:11434")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: ChatRequest) async throws -> ChatResponse {
        var urlRequest = URLRequest(url: Self.baseURL.appendingPathComponent("v1/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 90
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw BellAIServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = (json["error"] as? [String: Any])?["message"] as? String
                    ?? json["error"] as? String,
               !message.isEmpty {
                throw BellAIServiceError.server(http.statusCode, String(message.prefix(1_000)))
            }
            throw BellAIServiceError.http(http.statusCode)
        }
        guard let result = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
              let choice = result.choices.first,
              choice.finish_reason != nil, choice.message.role == "assistant" else {
            throw BellAIServiceError.invalidResponse
        }
        return ChatResponse(model: result.model, message: choice.message, done: true)
    }
}


// Wire format for the server's OpenAI-compatible /v1/chat/completions endpoint.
private struct ChatCompletionResponse: Decodable {
    let model: String
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
        let finish_reason: String?
    }
}
