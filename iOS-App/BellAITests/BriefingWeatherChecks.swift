import Foundation

private final class WeatherURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var malformed = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(url.scheme == "https" && url.host == "api.openweathermap.org")
        precondition(query.contains(URLQueryItem(name: "appid", value: "test-key")))
        precondition(query.contains(URLQueryItem(name: "units", value: "metric")))
        precondition(query.contains(URLQueryItem(name: "lat", value: "32.52321")))
        let current = #"{"name":"Ruston","main":{"temp":20,"temp_max":99,"temp_min":-99},"weather":[{"id":800,"description":"clear sky","icon":"01n"}]}"#
        let formatter = ISO8601DateFormatter()
        let dates = ["2026-10-25T17:00:00Z", "2026-10-25T21:00:00Z", "2026-10-26T03:00:00Z", "2026-10-26T06:00:00Z"]
        let temps = [-50, 25, 15, 100]
        let entries = zip(dates, temps).map { date, temp in
            "{\"dt\":\(formatter.date(from: date)!.timeIntervalSince1970),\"main\":{\"temp\":\(temp)}}"
        }.joined(separator: ",")
        let forecast = "{\"city\":{\"timezone\":-18000},\"list\":[\(entries)]}"
        let body = Self.malformed ? "invalid" : (url.lastPathComponent == "weather" ? current : forecast)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class StubBriefingWeather: BriefingWeatherProviding {
    var calls = 0
    var error: Error?
    func fetch() async throws -> BriefingWeather {
        calls += 1
        if let error { throw error }
        return BriefingWeather(
            locationName: "Chicago", temperature: .init(value: 58, unit: .fahrenheit),
            condition: "Clear", symbolName: "sun.max", high: .init(value: 71, unit: .fahrenheit),
            low: .init(value: 49, unit: .fahrenheit),
            attributionURL: URL(string: "https://example.com/attribution")!
        )
    }
}

@main
struct BriefingWeatherChecks {
    @MainActor
    static func main() async throws {
        try await checkOpenWeatherHTTP()
        let service = StubBriefingWeather()
        let model = BriefingWeatherViewModel(service: service)
        precondition(model.weather == nil && model.temperatureText(nil) == "—")
        await model.refresh()
        precondition(model.weather?.locationName == "Chicago")
        precondition(model.weather?.symbolName == "sun.max")
        precondition(model.weather?.high?.converted(to: .fahrenheit).value == 71)
        precondition(model.weather?.low?.converted(to: .fahrenheit).value == 49)
        precondition(!model.isLoading && model.errorMessage == nil)

        service.error = BriefingLocationError.permissionDenied
        await model.refresh()
        precondition(model.weather == nil && !model.isLoading)
        precondition(model.errorMessage?.contains("Settings") == true)

        service.error = NSError(domain: "MockWeather", code: 401)
        await model.refresh()
        precondition(model.weather == nil && model.errorMessage == "Weather is unavailable. Please try again.")

        service.error = nil
        await model.refresh()
        precondition(model.weather != nil && model.errorMessage == nil)
        service.error = CancellationError()
        await model.refresh()
        precondition(model.errorMessage == nil && !model.isLoading)
        precondition(service.calls == 5)
        print("All briefing weather checks passed.")
    }

    @MainActor
    private static func checkOpenWeatherHTTP() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeatherURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = OpenWeatherClient(apiKey: "test-key", session: session)
        let now = ISO8601DateFormatter().date(from: "2026-10-25T18:00:00Z")!
        let weather = try await client.fetch(latitude: 32.52321, longitude: -92.63793, now: now)
        precondition(weather.locationName == "Ruston" && weather.condition == "Clear Sky")
        precondition(weather.symbolName == "moon.stars")
        precondition(weather.temperature.value == 20 && weather.high?.value == 25 && weather.low?.value == 15)
        precondition(OpenWeatherClient.symbol(for: 800, night: false) == "sun.max")
        precondition(OpenWeatherClient.symbol(for: 501, night: false) == "cloud.rain")
        precondition(OpenWeatherClient.symbol(for: 601, night: true) == "cloud.snow")

        for status in [401, 403, 429, 500] {
            WeatherURLProtocol.status = status
            do {
                _ = try await client.fetch(latitude: 32.52321, longitude: -92.63793, now: now)
                preconditionFailure("Expected HTTP error")
            } catch let error as OpenWeatherError {
                switch (status, error) {
                case (401, .unauthorized), (403, .unauthorized), (429, .rateLimited), (500, .server): break
                default: preconditionFailure("Wrong HTTP error mapping")
                }
            }
        }
        WeatherURLProtocol.status = 200
        WeatherURLProtocol.malformed = true
        do {
            _ = try await client.fetch(latitude: 32.52321, longitude: -92.63793)
            preconditionFailure("Expected decoding error")
        } catch OpenWeatherError.invalidResponse {}
        WeatherURLProtocol.malformed = false
        for key in ["", "$(OPENWEATHER_API_KEY)", "YOUR_OPENWEATHER_API_KEY"] {
            do {
                try OpenWeatherClient(apiKey: key).validateConfiguration()
                preconditionFailure("Expected missing key")
            } catch OpenWeatherError.missingKey {}
        }
    }
}
