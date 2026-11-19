import Foundation

enum ChatClientError: LocalizedError {
    case badAddress, noModel, server(Int, String?)

    var errorDescription: String? {
        switch self {
        case .badAddress: "The server's address in Settings (⌘,) isn't valid."
        case .noModel: "The server has no models to choose from. Enter a model name in Settings (⌘,)."
        case .server(let code, let message): "The server answered HTTP \(code)" + (message.map { ": \($0)" } ?? ".")
        }
    }
}

// talks to any server that answers like OpenAI: Ollama, the BellAI Mac server, and so on
struct ChatClient {
    private let base: URL

    // the chat server's address from Settings, looked up on use so a new one applies right away
    init?() {
        guard let url = URL(string: "http://\(ServerSettings.address(.chat))") else { return nil }
        base = url
    }

    func models() async throws -> [String] {
        struct List: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]
        }
        var request = URLRequest(url: base.appendingPathComponent("v1/models"))
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(List.self, from: data).data.map(\.id)
    }

    // the reply as it is written, piece by piece
    func stream(model: String, messages: [Message]) -> AsyncThrowingStream<String, Error> {
        struct Body: Encodable {
            struct Turn: Encodable { let role: String; let content: String }
            let model: String
            let stream = true
            let messages: [Turn]
        }
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta
            }
            let choices: [Choice]
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120 // the first word can wait on a model loading
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(Body(
                        model: model,
                        messages: messages.map { .init(role: $0.role.rawValue, content: $0.text) }))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte); if body.count > 2_000 { break } }
                        throw ChatClientError.server(http.statusCode, Self.message(in: body))
                    }
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if let piece = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8))
                            .choices.first?.delta.content, !piece.isEmpty {
                            continuation.yield(piece)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // {"error": "..."} or {"error": {"message": "..."}}
    private static func message(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let text = (json["error"] as? [String: Any])?["message"] as? String ?? json["error"] as? String
        return text.flatMap { $0.isEmpty ? nil : String($0.prefix(500)) }
    }
}
