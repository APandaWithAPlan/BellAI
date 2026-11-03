import CoreLocation
import Foundation
import MapKit
import WeatherKit

struct BriefingWeather {
    let locationName: String
    let temperature: Measurement<UnitTemperature>
    let condition: String
    let symbolName: String
    let high: Measurement<UnitTemperature>? // today's, from the daily forecast
    let low: Measurement<UnitTemperature>?
    let attribution: BriefingWeatherAttribution
}

// what Apple requires next to its weather: the Apple Weather mark and a link to the legal page
struct BriefingWeatherAttribution {
    let markURL: URL
    let legalURL: URL
}

@MainActor
protocol BriefingWeatherProviding {
    func fetch() async throws -> BriefingWeather
}

@MainActor
final class BriefingWeatherService: BriefingWeatherProviding {
    private let location = BriefingLocationService()

    func fetch() async throws -> BriefingWeather {
        let coordinate = try await location.currentLocation()
        async let city = Self.cityName(for: coordinate)
        let weather: (CurrentWeather, Forecast<DayWeather>)
        let attribution: WeatherAttribution
        do {
            weather = try await WeatherService.shared.weather(for: coordinate, including: .current, .daily)
            attribution = try await WeatherService.shared.attribution
        } catch {
            throw BriefingWeatherError(mapping: error) ?? error
        }
        let (current, daily) = weather
        let today = daily.forecast.first
        let name = await city
        try Task.checkCancellation()
        return BriefingWeather(
            locationName: name ?? "Current location",
            temperature: current.temperature,
            condition: current.condition.description,
            symbolName: current.symbolName,
            high: today?.highTemperature,
            low: today?.lowTemperature,
            // the dark mark, because the screen behind it is always light
            attribution: BriefingWeatherAttribution(markURL: attribution.combinedMarkDarkURL, legalURL: attribution.legalPageURL)
        )
    }

    // WeatherKit gives the weather, not the place's name
    private static func cityName(for location: CLLocation) async -> String? {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            let geocoding = MKReverseGeocodingRequest(location: location)
            let place = try? await geocoding?.mapItems.first
            return place?.addressRepresentations?.cityName ?? place?.addressRepresentations?.cityWithContext
        } else {
            return (try? await CLGeocoder().reverseGeocodeLocation(location).first)?.locality
        }
    }
}

enum BriefingWeatherError: LocalizedError {
    case notEnabled

    // nil for anything that isn't Apple turning the app away. when the app isn't entitled, WeatherKit usually
    // doesn't throw permissionDenied, its token service fails first and that error comes through as it is
    init?(mapping error: Error) {
        if let error = error as? WeatherError, case .permissionDenied = error {
            self = .notEnabled
        } else if (error as NSError).domain.contains("JWTAuthenticator") {
            self = .notEnabled
        } else {
            return nil
        }
    }

    var errorDescription: String? {
        "Apple Weather isn't enabled for this build of BellAI. Turn on the WeatherKit capability for the app in your developer account, then rebuild."
    }
}

/// Requests a single, city-level location only while the briefing is open.
@MainActor
private final class BriefingLocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<CLLocation, Error>?
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async throws -> CLLocation {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                requestIfAuthorized()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    private func requestIfAuthorized() {
        guard pending != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard timeout == nil else { return }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                self?.finish(.failure(BriefingLocationError.unavailable))
            }
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(BriefingLocationError.permissionDenied))
        @unknown default:
            finish(.failure(BriefingLocationError.unavailable))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 300
        }) else { return }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .locationUnknown { return }
        finish(.failure(error))
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }
}

enum BriefingLocationError: LocalizedError {
    case permissionDenied, unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Allow location access for BellAI in Settings to see local weather."
        case .unavailable: "Your location is unavailable. Please try again."
        }
    }
}
