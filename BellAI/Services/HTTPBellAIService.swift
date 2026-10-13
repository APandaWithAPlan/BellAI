import Foundation

@MainActor
protocol BellAIService {
    func send(_ request: ChatRequest) async throws -> ChatResponse
}

enum BellAIServiceError: LocalizedError {
    case missingKey
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Ollama API key is missing. Configure OLLAMA_API_KEY in your local Debug configuration."
        case .invalidResponse:
            "Ollama returned an invalid or incomplete response. Please try again."
        case .http(401), .http(403):
            "Ollama rejected the request. Check your API key and model access."
        case .http(429):
            "Ollama's usage limit was reached. Please try again later."
        case .http(let code):
            "Ollama request failed (HTTP \(code)). Please try again."
        }
    }
}

@MainActor
struct HTTPBellAIService: BellAIService {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String? = nil, session: URLSession = .shared) {
        // Personal development key only; distributed apps should use a backend.
        self.apiKey = apiKey ?? (Bundle.main.object(forInfoDictionaryKey: "OLLAMA_API_KEY") as? String ?? "")
        self.session = session
    }

    func send(_ request: ChatRequest) async throws -> ChatResponse {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix("$(") else {
            throw BellAIServiceError.missingKey
        }

        var urlRequest = URLRequest(url: URL(string: "https://ollama.com/api/chat")!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 90
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw BellAIServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BellAIServiceError.http(http.statusCode)
        }
        guard let result = try? JSONDecoder().decode(ChatResponse.self, from: data),
              result.done, result.message.role == "assistant" else {
            throw BellAIServiceError.invalidResponse
        }
        return result
    }
}
