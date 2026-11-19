import Foundation

@MainActor
protocol SpeechTranscribing {
    /// What was said in a wav recording (16 kHz, mono, 16 bit), empty if nobody was speaking
    func transcribe(_ wav: Data) async throws -> String
}

// POST /transcribe on the voice server, same host as the websocket. whisper runs on the mac, so the audio never leaves your network
@MainActor
struct HTTPSpeechTranscriber: SpeechTranscribing {
    private let fixedURL: URL?
    private let session: URLSession

    // no baseURL means the voice server's address from Settings, looked up on use
    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.fixedURL = baseURL
        self.session = session
    }

    private var baseURL: URL {
        fixedURL ?? URL(string: "http://\(WebSocketVoiceService.configuredHost)")!
    }

    func transcribe(_ wav: Data) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "transcribe"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60 // the first one after a restart waits for the model
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wav

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BellAIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // errors come back as {"detail": "..."}
            let detail = (try? JSONDecoder().decode(Reply.self, from: data))?.detail
            throw BellAIServiceError.server(http.statusCode, String((detail ?? "").prefix(1_000)))
        }
        guard let text = (try? JSONDecoder().decode(Reply.self, from: data))?.text else {
            throw BellAIServiceError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Reply: Decodable {
        let text: String?
        let detail: String?
    }
}
