import Foundation

@MainActor
struct HTTPRoutineService {
    var session: URLSession = .shared

    func load() async throws -> [Routine] {
        struct Result: Decodable { let routines: [Routine] }
        return try JSONDecoder().decode(Result.self, from: await perform("GET")).routines
    }

    func create(_ routine: Routine) async throws -> Routine {
        try JSONDecoder().decode(Routine.self, from: await perform("POST", body: JSONEncoder().encode(routine)))
    }

    func delete(_ id: UUID) async throws {
        _ = try await perform("DELETE", path: "/\(id.uuidString.lowercased())")
    }

    private func perform(_ method: String, path: String = "", body: Data? = nil) async throws -> Data {
        let url = URL(string: "http://\(ServerSettings.address(.data))/routines\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BellAIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let detail: String }
            if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
                throw BellAIServiceError.server(http.statusCode, failure.detail)
            }
            throw BellAIServiceError.http(http.statusCode)
        }
        return data
    }
}
