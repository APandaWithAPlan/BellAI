import Foundation
#if os(iOS)
import CoreMotion
import HealthKit
#endif

#if os(iOS)
struct WorkoutIntensityService: WorkoutIntensityProviding {
    private let store = HKHealthStore()
    private let motion = CMMotionActivityManager()
    private static let window: TimeInterval = 120 // heart rate and motion older than this say nothing about now
    private static let fallbackAge = 30.0

    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }

    func requestAccess() async {
        if HKHealthStore.isHealthDataAvailable() {
            let read: Set<HKObjectType> = [heartRateType, HKCharacteristicType(.dateOfBirth)]
            try? await store.requestAuthorization(toShare: [], read: read)
        }
        _ = await recentMotion() // the first ask is what shows the motion permission sheet
    }

    func current() async -> MusicIntensity? {
        async let heartRate = recentHeartRate()
        async let activity = recentMotion()
        return MusicIntensity.resolve(heartRate: await heartRate, maxHeartRate: maxHeartRate(), motion: await activity)
    }

    // 220 minus age is the usual rough maximum. without a birth date shared, a 30 year old is assumed
    private func maxHeartRate() -> Double {
        let born = (try? store.dateOfBirthComponents())?.date
        let age = born.map { Calendar.current.dateComponents([.year], from: $0, to: .now).year.map(Double.init) ?? Self.fallbackAge }
        return 220 - (age ?? Self.fallbackAge)
    }

    // the average of the last two minutes, or nil if nothing was recorded or shared
    private func recentHeartRate() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: .now.addingTimeInterval(-Self.window), end: .now)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                continuation.resume(returning: result?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            }
            store.execute(query)
        }
    }

    // the latest thing the phone is fairly sure of, or nil if it can't tell or motion access was refused
    private func recentMotion() async -> MotionKind? {
        guard CMMotionActivityManager.isActivityAvailable() else { return nil }
        return await withCheckedContinuation { continuation in
            motion.queryActivityStarting(from: .now.addingTimeInterval(-Self.window), to: .now, to: .main) { activities, _ in
                let sure = activities?.last { $0.confidence != .low }
                continuation.resume(returning: sure.flatMap(Self.kind))
            }
        }
    }

    private static func kind(_ activity: CMMotionActivity) -> MotionKind? {
        if activity.running { .running }
        else if activity.cycling { .cycling }
        else if activity.walking { .walking }
        else if activity.stationary { .stationary }
        else { nil }
    }
}
#else
// no heart rate or motion sensors here
struct WorkoutIntensityService: WorkoutIntensityProviding {
    func requestAccess() async {}
    func current() async -> MusicIntensity? { nil }
}
#endif
