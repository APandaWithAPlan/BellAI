import Foundation

enum MealLoggingError: LocalizedError {
    case unavailable
    case notAllowed

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health isn't available on this device."
        case .notAllowed: "Allow BellAI to write nutrition in Apple Health (Health app > profile picture > Apps > BellAI) and try again."
        }
    }
}

@MainActor
protocol MealLogging {
    /// Saves a meal's calories and protein. Throws what to tell the person if it can't.
    func log(_ nutrition: Nutrition, name: String) async throws
}

// where meals are logged on this device, nil where there is nothing to log to
@MainActor
func standardMealLogger() -> (any MealLogging)? {
    #if os(iOS)
    HealthMealLogger()
    #else
    nil
    #endif
}

#if os(iOS)
import HealthKit

// writes the meal to Apple Health, where the Wellness screen reads it back
@MainActor
struct HealthMealLogger: MealLogging {
    private let store = HKHealthStore()

    func log(_ nutrition: Nutrition, name: String) async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let energy = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              let protein = HKQuantityType.quantityType(forIdentifier: .dietaryProtein) else {
            throw MealLoggingError.unavailable
        }
        // asks the first time, and again only if a type is new
        try await store.requestAuthorization(toShare: [energy, protein], read: [])
        guard store.authorizationStatus(for: energy) == .sharingAuthorized,
              store.authorizationStatus(for: protein) == .sharingAuthorized else {
            throw MealLoggingError.notAllowed
        }
        let now = Date()
        let metadata = [HKMetadataKeyFoodType: String(name.prefix(100))]
        try await store.save([
            HKQuantitySample(type: energy, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(nutrition.calories)),
                             start: now, end: now, metadata: metadata),
            HKQuantitySample(type: protein, quantity: HKQuantity(unit: .gram(), doubleValue: Double(nutrition.proteinGrams)),
                             start: now, end: now, metadata: metadata)
        ])
    }
}
#endif
