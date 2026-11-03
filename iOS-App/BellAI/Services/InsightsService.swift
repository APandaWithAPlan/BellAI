import Foundation

// food and workout ideas for today, worked out by the Insights server from the meals and preferences it is sent
struct Insights: Equatable, Decodable {
    struct Food: Equatable, Decodable, Identifiable {
        let title: String
        let why: String
        let kcal: Double?
        let proteinG: Double?
        var id: String { title }

        private enum CodingKeys: String, CodingKey {
            case title, why, kcal
            case proteinG = "protein_g"
        }

        init(title: String, why: String = "", kcal: Double? = nil, proteinG: Double? = nil) {
            self.title = title
            self.why = why
            self.kcal = kcal
            self.proteinG = proteinG
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            title = try values.decode(String.self, forKey: .title)
            why = try values.decodeIfPresent(String.self, forKey: .why) ?? ""
            kcal = try values.decodeIfPresent(Double.self, forKey: .kcal)
            proteinG = try values.decodeIfPresent(Double.self, forKey: .proteinG)
        }
    }

    struct Workout: Equatable, Decodable, Identifiable {
        let title: String
        let why: String
        let minutes: Double?
        let intensity: String?
        var id: String { title }

        init(title: String, why: String = "", minutes: Double? = nil, intensity: String? = nil) {
            self.title = title
            self.why = why
            self.minutes = minutes
            self.intensity = intensity
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            title = try values.decode(String.self, forKey: .title)
            why = try values.decodeIfPresent(String.self, forKey: .why) ?? ""
            minutes = try values.decodeIfPresent(Double.self, forKey: .minutes)
            intensity = try values.decodeIfPresent(String.self, forKey: .intensity)
        }

        private enum CodingKeys: String, CodingKey { case title, why, minutes, intensity }
    }

    let status: String // the biggest problem with the day, like low_protein, or on_track
    let summary: String
    let foods: [Food]
    let workouts: [Workout]

    private enum CodingKeys: String, CodingKey {
        case status, summary
        case foods = "food_recommendations"
        case workouts = "workout_recommendations"
    }

    init(status: String, summary: String, foods: [Food] = [], workouts: [Workout] = []) {
        self.status = status
        self.summary = summary
        self.foods = foods
        self.workouts = workouts
    }
}

@MainActor
protocol InsightsService {
    func insights(for preferences: FoodPreferences, meals: [LoggedMeal]) async throws -> Insights
}

// POST /insights on the voice server, which passes it on to the Insights server, same host as the websocket
@MainActor
struct HTTPInsightsService: InsightsService {
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

    func insights(for preferences: FoodPreferences, meals: [LoggedMeal]) async throws -> Insights {
        let body: [String: Any] = [
            "user": preferences.requestFields,
            "meals": try meals.map { meal -> Any in
                var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(meal.nutrients)) as? [String: Any] ?? [:]
                fields["name"] = meal.name
                return fields
            },
        ]
        var request = URLRequest(url: baseURL.appending(path: "insights"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90 // the chat model writes the ideas, which takes a few seconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BellAIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // errors come back as {"detail": "..."}
            let detail = (try? JSONDecoder().decode(ErrorReply.self, from: data))?.detail
            if let detail, !detail.isEmpty { throw BellAIServiceError.server(http.statusCode, String(detail.prefix(500))) }
            throw BellAIServiceError.http(http.statusCode)
        }
        guard let insights = try? JSONDecoder().decode(Insights.self, from: data), !insights.summary.isEmpty else {
            throw BellAIServiceError.invalidResponse
        }
        return insights
    }

    private struct ErrorReply: Decodable { let detail: String }
}
