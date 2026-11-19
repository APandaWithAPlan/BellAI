import Foundation

@MainActor
protocol MailService {
    /// newest first
    func recent(limit: Int) async throws -> [MailItem]
    /// drafts waiting to be sent or discarded
    func pendingDrafts() async throws -> [MailDraft]
    /// BellAI writes a reply to `replyTo`, or a new email to `to`. Nothing is sent.
    func writeDraft(saying: String, to: String?, replyTo: Int?) async throws -> MailDraft
    func send(_ draft: MailDraft) async throws
    func discard(_ draft: MailDraft) async throws
}

enum MailServiceError: LocalizedError {
    case message(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .invalidResponse: "The mail server sent something unexpected. Please try again."
        }
    }
}

// /mail and /drafts on the voice server, passed on to the mail server on the Mac, same host as the websocket
@MainActor
struct HTTPMailService: MailService {
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

    func recent(limit: Int) async throws -> [MailItem] {
        let data = try await perform("GET", "mail", query: [URLQueryItem(name: "limit", value: String(limit))])
        return try decode(Mail.self, from: data).mail
    }

    func pendingDrafts() async throws -> [MailDraft] {
        let data = try await perform("GET", "drafts", query: [URLQueryItem(name: "status", value: "pending")])
        return try decode(Drafts.self, from: data).drafts
    }

    func writeDraft(saying: String, to: String?, replyTo: Int?) async throws -> MailDraft {
        var body: [String: Any] = ["instruction": saying]
        if let to { body["to"] = to }
        if let replyTo { body["reply_to"] = replyTo }
        let data = try await perform("POST", "drafts", body: try JSONSerialization.data(withJSONObject: body), timeout: 120)
        return try decode(MailDraft.self, from: data)
    }

    func send(_ draft: MailDraft) async throws {
        _ = try await perform("POST", "drafts/\(draft.id)/send", timeout: 60)
    }

    func discard(_ draft: MailDraft) async throws {
        _ = try await perform("POST", "drafts/\(draft.id)/discard")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else { throw MailServiceError.invalidResponse }
        return value
    }

    private func perform(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
                         timeout: TimeInterval = 15) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = timeout // writing a draft waits on the chat model
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MailServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // errors come back as {"detail": "..."} and are already worded for people
            if let detail = (try? JSONDecoder().decode(ErrorReply.self, from: data))?.detail, !detail.isEmpty {
                throw MailServiceError.message(String(detail.prefix(500)))
            }
            throw MailServiceError.message("The mail server request failed (HTTP \(http.statusCode)). Please try again.")
        }
        return data
    }

    private struct Mail: Decodable { let mail: [MailItem] }
    private struct Drafts: Decodable { let drafts: [MailDraft] }
    private struct ErrorReply: Decodable { let detail: String }
}
