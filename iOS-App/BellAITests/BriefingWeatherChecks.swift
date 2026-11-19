import Foundation
import WeatherKit

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
            attribution: BriefingWeatherAttribution(
                markURL: URL(string: "https://example.com/mark.png")!, legalURL: URL(string: "https://example.com/legal")!
            )
        )
    }
}

@main
struct BriefingWeatherChecks {
    @MainActor
    static func main() async throws {
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
        await checkErrorMapping()
        print("All briefing weather checks passed.")
    }

    // only Apple turning the app away gets its own message, anything else stays the generic one
    @MainActor
    private static func checkErrorMapping() async {
        precondition(BriefingWeatherError(mapping: WeatherError.permissionDenied) != nil)
        precondition(BriefingWeatherError(mapping: WeatherError.unknown) == nil)
        precondition(BriefingWeatherError(mapping: NSError(domain: "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors", code: 2)) != nil)
        precondition(BriefingWeatherError(mapping: URLError(.notConnectedToInternet)) == nil)
        precondition(BriefingWeatherError.notEnabled.localizedDescription.contains("WeatherKit"))
        let service = StubBriefingWeather()
        service.error = BriefingWeatherError.notEnabled
        let model = BriefingWeatherViewModel(service: service)
        await model.refresh()
        precondition(model.weather == nil && model.errorMessage?.contains("WeatherKit") == true)
    }
}
