import Foundation

@MainActor
struct OpenWeatherClient {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String? = nil, session: URLSession = .shared) {
        self.apiKey = (apiKey ?? Bundle.main.object(forInfoDictionaryKey: "OPENWEATHER_API_KEY") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func validateConfiguration() throws {
        guard !apiKey.isEmpty, !apiKey.hasPrefix("$("), apiKey != "YOUR_OPENWEATHER_API_KEY" else {
            throw OpenWeatherError.missingKey
        }
    }

    func fetch(latitude: Double, longitude: Double, now: Date = .now) async throws -> BriefingWeather {
        try validateConfiguration()
        async let current: Current = load("weather", latitude: latitude, longitude: longitude)
        async let forecast: Forecast = load("forecast", latitude: latitude, longitude: longitude)
        let (conditions, predictions) = try await (current, forecast)
        try Task.checkCancellation()
        guard let condition = conditions.weather.first else { throw OpenWeatherError.invalidResponse }
        var calendar = Calendar(identifier: .gregorian)
        guard let timezone = TimeZone(secondsFromGMT: predictions.city.timezone) else {
            throw OpenWeatherError.invalidResponse
        }
        calendar.timeZone = timezone
        // This endpoint contains future 3-hour samples, not a full-day min/max.
        let remaining = predictions.list.filter {
            let date = Date(timeIntervalSince1970: $0.dt)
            return date >= now && calendar.isDate(date, inSameDayAs: now)
        }.map(\.main.temp)
        let temperatures = remaining.isEmpty ? [] : [conditions.main.temp] + remaining
        return BriefingWeather(
            locationName: conditions.name.isEmpty ? "Current location" : conditions.name,
            temperature: .init(value: conditions.main.temp, unit: .celsius),
            condition: condition.description.capitalized,
            symbolName: Self.symbol(for: condition.id, night: condition.icon.hasSuffix("n")),
            high: temperatures.max().map { .init(value: $0, unit: .celsius) },
            low: temperatures.min().map { .init(value: $0, unit: .celsius) },
            attributionURL: URL(string: "https://openweathermap.org/")!
        )
    }

    private func load<T: Decodable>(_ endpoint: String, latitude: Double, longitude: Double) async throws -> T {
        var url = URLComponents(string: "https://api.openweathermap.org/data/2.5/\(endpoint)")!
        url.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "appid", value: apiKey),
            URLQueryItem(name: "units", value: "metric")
        ]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw OpenWeatherError.invalidResponse }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw OpenWeatherError.unauthorized
        case 429: throw OpenWeatherError.rateLimited
        default: throw OpenWeatherError.server
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw OpenWeatherError.invalidResponse }
    }

    static func symbol(for code: Int, night: Bool) -> String {
        switch code {
        case 200..<300: "cloud.bolt.rain"
        case 300..<400: "cloud.drizzle"
        case 511: "cloud.sleet"
        case 500..<600: "cloud.rain"
        case 600..<700: "cloud.snow"
        case 781: "tornado"
        case 700..<800: "cloud.fog"
        case 800: night ? "moon.stars" : "sun.max"
        case 801, 802: night ? "cloud.moon" : "cloud.sun"
        case 803, 804: "cloud"
        default: "cloud"
        }
    }

    nonisolated private struct Temperature: Decodable { let temp: Double }
    nonisolated private struct Condition: Decodable { let id: Int; let description: String; let icon: String }
    nonisolated private struct Current: Decodable {
        let name: String
        let main: Temperature
        let weather: [Condition]
    }
    nonisolated private struct Forecast: Decodable {
        struct City: Decodable { let timezone: Int }
        struct Entry: Decodable { let dt: Double; let main: Temperature }
        let city: City
        let list: [Entry]
    }
}

enum OpenWeatherError: LocalizedError {
    case missingKey, unauthorized, rateLimited, invalidResponse, server

    var errorDescription: String? {
        switch self {
        case .missingKey: "Weather hasn’t been configured yet."
        case .unauthorized: "OpenWeather access is unavailable. Check the API key and its activation."
        case .rateLimited: "Weather updates are temporarily limited. Please try again later."
        case .invalidResponse: "The weather response could not be read. Please try again."
        case .server: "OpenWeather is unavailable. Please try again later."
        }
    }
}
