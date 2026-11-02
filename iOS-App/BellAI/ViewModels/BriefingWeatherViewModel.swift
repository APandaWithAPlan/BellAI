import Foundation
import Observation

@MainActor
@Observable
final class BriefingWeatherViewModel {
    private(set) var weather: BriefingWeather?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let service: any BriefingWeatherProviding

    init(service: (any BriefingWeatherProviding)? = nil) {
        self.service = service ?? BriefingWeatherService()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await service.fetch()
            try Task.checkCancellation()
            weather = result
        } catch is CancellationError {
            // Leaving Agenda cancels its request without displaying an error.
        } catch {
            weather = nil
            errorMessage = (error as? BriefingLocationError)?.localizedDescription
                ?? (error as? OpenWeatherError)?.localizedDescription
                ?? "Weather is unavailable. Please try again."
            let failure = error as NSError
            print("[Weather] \(failure.domain) (\(failure.code))")
        }
    }

    func temperatureText(_ value: Measurement<UnitTemperature>?) -> String {
        guard let value else { return "—" }
        return value.formatted(.measurement(width: .narrow, usage: .weather,
                                           numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
