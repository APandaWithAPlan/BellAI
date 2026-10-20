import Foundation

// what the voice server sends back
enum VoiceEvent: Equatable {
    case text(String)
    case sentence(index: Int, text: String, audio: Data) // audio is a full wav
    case done
}

enum VoiceStreamError: LocalizedError, Equatable {
    case server(String)
    case endedEarly

    var errorDescription: String? {
        switch self {
        case .server(let message):
            "The voice server reported an error: \(message)"
        case .endedEarly:
            "The voice server closed the connection before the reply finished."
        }
    }
}

@MainActor
protocol VoiceStreamService {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<VoiceEvent, Error>
}

// websocket to the voice server
@MainActor
struct WebSocketVoiceService: VoiceStreamService {
    private let url: URL
    private let session: URLSession

    init(url: URL = WebSocketVoiceService.configuredURL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    // VOICE_SERVER_HOST from Info.plist, else ai-server:8000
    nonisolated static var configuredHost: String {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "VOICE_SERVER_HOST") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return configured?.isEmpty == false && configured?.hasPrefix("$(") == false ? configured! : "ai-server:8000"
    }

    nonisolated static var configuredURL: URL {
        URL(string: "ws://\(configuredHost)/ws")!
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<VoiceEvent, Error> {
        let socket = session.webSocketTask(with: url)
        return AsyncThrowingStream { continuation in
            let reader = Task {
                do {
                    socket.resume()
                    let body = try JSONEncoder().encode(request)
                    try await socket.send(.string(String(decoding: body, as: UTF8.self)))

                    // a "sentence" frame is followed by its audio
                    var waitingForAudio: (index: Int, text: String)?
                    while true {
                        switch try await socket.receive() {
                        case .data(let audio):
                            guard let sentence = waitingForAudio else { continue }
                            waitingForAudio = nil
                            continuation.yield(.sentence(index: sentence.index, text: sentence.text, audio: audio))
                        case .string(let json):
                            guard let frame = try? JSONDecoder().decode(ServerFrame.self, from: Data(json.utf8)) else { continue }
                            switch frame.type {
                            case "text":
                                if let delta = frame.delta, !delta.isEmpty { continuation.yield(.text(delta)) }
                            case "sentence":
                                waitingForAudio = (frame.index ?? 0, frame.text ?? "")
                            case "done":
                                continuation.yield(.done)
                                continuation.finish()
                                return
                            case "error":
                                throw VoiceStreamError.server(frame.message ?? "unknown error")
                            default:
                                break // tts_error, no audio for that sentence but text keeps coming
                            }
                        @unknown default:
                            break
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // stream dropped, close everything
            continuation.onTermination = { _ in
                reader.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}

private struct ServerFrame: Decodable {
    let type: String
    let delta: String?
    let index: Int?
    let text: String?
    let message: String?
}
