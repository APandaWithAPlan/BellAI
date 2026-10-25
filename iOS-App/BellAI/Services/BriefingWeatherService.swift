import CoreLocation
import Foundation
import MapKit

struct BriefingWeather {
    let locationName: String
    let temperature: Measurement<UnitTemperature>
    let condition: String
    let symbolName: String
    let high: Measurement<UnitTemperature>?
    let low: Measurement<UnitTemperature>?
    let attributionURL: URL
}

@MainActor
protocol BriefingWeatherProviding {
    func fetch() async throws -> BriefingWeather
}

@MainActor
final class BriefingWeatherService: BriefingWeatherProviding {
    private let location = BriefingLocationService()
    private let client: OpenWeatherClient

    init(client: OpenWeatherClient? = nil) {
        self.client = client ?? OpenWeatherClient()
    }

    func fetch() async throws -> BriefingWeather {
        try client.validateConfiguration()
        let coordinate = try await location.currentLocation()
        async let response = client.fetch(latitude: coordinate.coordinate.latitude, longitude: coordinate.coordinate.longitude)
        let geocoding = MKReverseGeocodingRequest(location: coordinate)
        let place = try? await geocoding?.mapItems.first
        let result = try await response
        try Task.checkCancellation()
        return BriefingWeather(
            locationName: place?.addressRepresentations?.cityName ?? place?.addressRepresentations?.cityWithContext ?? result.locationName,
            temperature: result.temperature, condition: result.condition, symbolName: result.symbolName,
            high: result.high, low: result.low, attributionURL: result.attributionURL
        )
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
