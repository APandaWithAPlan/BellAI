import Foundation
import Observation
#if os(iOS)
import HealthKit
#endif

@MainActor
@Observable
final class WellnessHealthModel {
    private(set) var steps: Double?
    private(set) var activeCalories: Double?
    private(set) var waterML: Double?
    private(set) var dietaryCalories: Double?
    private(set) var proteinGrams: Double?
    private(set) var workoutTitle: String?
    private(set) var workoutMinutes: Double?
    private(set) var isLoading = false
    var errorMessage: String?

    #if os(iOS)
    private let store = HKHealthStore()
    private let quantities: [HKQuantityTypeIdentifier] = [
        .stepCount, .activeEnergyBurned, .dietaryWater, .dietaryEnergyConsumed, .dietaryProtein
    ]
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    #else
    var isAvailable: Bool { false }
    #endif

    // Completion means the permission sheet was handled, not that read access was granted.
    func requestAccess() async -> Bool {
        guard isAvailable, !isLoading else { return false }
        #if os(iOS)
        isLoading = true
        defer { isLoading = false }
        do {
            var types = Set<HKObjectType>(quantities.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
            types.insert(HKObjectType.workoutType())
            try await store.requestAuthorization(toShare: [], read: types)
            return true
        } catch {
            errorMessage = "Couldn't request Apple Health access. \(error.localizedDescription)"
        }
        #endif
        return false
    }

    func refresh() async {
        guard isAvailable, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        // Clear old values so revoked access never leaves stale health information on screen.
        steps = nil
        activeCalories = nil
        waterML = nil
        dietaryCalories = nil
        proteinGrams = nil
        workoutTitle = nil
        workoutMinutes = nil
        errorMessage = nil
        #if os(iOS)
        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)
        do {
            steps = try await total(.stepCount, unit: .count(), predicate: predicate)
            activeCalories = try await total(.activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
            waterML = try await total(.dietaryWater, unit: .literUnit(with: .milli), predicate: predicate)
            dietaryCalories = try await total(.dietaryEnergyConsumed, unit: .kilocalorie(), predicate: predicate)
            proteinGrams = try await total(.dietaryProtein, unit: .gram(), predicate: predicate)
            if let workout = try await latestWorkout(predicate: predicate) {
                workoutTitle = Self.workoutName(workout.workoutActivityType)
                workoutMinutes = workout.duration / 60
            }
        } catch {
            errorMessage = "Couldn't refresh Apple Health. \(error.localizedDescription)"
        }
        #endif
    }

    #if os(iOS)
    private func total(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit)) }
            }
            store.execute(query)
        }
    }

    private func latestWorkout(predicate: NSPredicate) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKWorkout) }
            }
            store.execute(query)
        }
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .yoga: "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength training"
        case .highIntensityIntervalTraining: "Interval training"
        default: "Workout"
        }
    }
    #endif
}
