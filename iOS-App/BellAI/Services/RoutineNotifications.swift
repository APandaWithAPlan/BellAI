import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class RoutineNotifications {
    static let shared = RoutineNotifications()
    private(set) var message: String?
    private(set) var permissionDenied = false
    private let center = UNUserNotificationCenter.current()
    private let delegate = RoutineNotificationDelegate()
    private var pendingUpdate: Task<[Routine], Error>?
    private var knownRoutines: [Routine] = []
    private static let prefix = "routine."

    private init() {
        center.delegate = delegate
    }

    // Serialize fetches, deletions and saves so an older response cannot undo a newly saved reminder.
    func refresh(requestPermission: Bool = false) async throws -> [Routine] {
        let previous = pendingUpdate
        let update = Task<[Routine], Error> { @MainActor in
            _ = try? await previous?.value
            let routines = try await HTTPRoutineService().load()
            self.knownRoutines = routines
            await self.synchronize(requestPermission: requestPermission)
            return routines
        }
        pendingUpdate = update
        return try await update.value
    }

    func saved(_ routine: Routine) async {
        let previous = pendingUpdate
        let update = Task<[Routine], Error> { @MainActor in
            _ = try? await previous?.value
            self.knownRoutines.removeAll { $0.id == routine.id }
            self.knownRoutines.append(routine)
            // Save succeeded; scheduling must not depend on another network request.
            await self.synchronize(requestPermission: true, removeStale: false)
            return self.knownRoutines
        }
        pendingUpdate = update
        _ = try? await update.value
    }

    func delete(_ routine: Routine) async throws {
        let previous = pendingUpdate
        let update = Task<[Routine], Error> { @MainActor in
            _ = try? await previous?.value
            try await HTTPRoutineService().delete(routine.id)
            self.knownRoutines.removeAll { $0.id == routine.id }
            let identifier = Self.identifier(routine)
            self.center.removePendingNotificationRequests(withIdentifiers: [identifier])
            self.center.removeDeliveredNotifications(withIdentifiers: [identifier])
            await self.synchronize(requestPermission: false, removeStale: false)
            return self.knownRoutines
        }
        pendingUpdate = update
        _ = try await update.value
    }

    private func synchronize(requestPermission: Bool, removeStale: Bool = true) async {
        do {
            var settings = await center.notificationSettings()
            if requestPermission && !knownRoutines.isEmpty && settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            }
            permissionDenied = settings.authorizationStatus == .denied
            guard [.authorized, .provisional].contains(settings.authorizationStatus) else {
                message = permissionDenied
                    ? "Notifications are off. Enable them in Settings to receive routine reminders."
                    : "Allow notifications to receive a daily reminder at each routine’s time."
                return
            }

            let pending = await center.pendingNotificationRequests()
            let desired = Set(knownRoutines.map { Self.identifier($0) })
            if removeStale {
                center.removePendingNotificationRequests(withIdentifiers: pending.compactMap {
                    $0.identifier.hasPrefix(Self.prefix) && !desired.contains($0.identifier) ? $0.identifier : nil
                })
            }
            // Stay within the system's pending-request budget, including other notifications.
            let reserved = pending.filter {
                !$0.identifier.hasPrefix(Self.prefix) || (!removeStale && !desired.contains($0.identifier))
            }.count
            let capacity = max(0, 64 - reserved)
            let routines = knownRoutines.sorted { ($0.time, $0.id.uuidString) < ($1.time, $1.id.uuidString) }
            for routine in routines.prefix(capacity) {
                try await center.add(Self.request(for: routine))
            }
            message = routines.count > capacity
                ? "Only \(capacity) routine reminders could be scheduled. This device’s notification limit has been reached."
                : "Daily reminders are scheduled in each routine’s saved timezone."
        } catch {
            message = "Your routines are saved, but reminders couldn’t be scheduled. \(error.localizedDescription) Pull to refresh to try again."
        }
    }

    static func identifier(_ routine: Routine) -> String {
        prefix + routine.id.uuidString.lowercased()
    }

    static func request(for routine: Routine) throws -> UNNotificationRequest {
        let parts = routine.time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute),
              let zone = TimeZone(identifier: routine.timezone) else {
            throw BellAIServiceError.invalidResponse
        }
        var date = DateComponents()
        date.calendar = Calendar(identifier: .gregorian)
        date.timeZone = zone
        date.hour = hour
        date.minute = minute
        date.second = 0
        let content = UNMutableNotificationContent()
        content.title = routine.name
        content.body = String(routine.actions.joined(separator: " • ").prefix(500))
        content.sound = .default
        content.userInfo = ["routineID": routine.id.uuidString]
        return UNNotificationRequest(identifier: identifier(routine), content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true))
    }
}

private final class RoutineNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
