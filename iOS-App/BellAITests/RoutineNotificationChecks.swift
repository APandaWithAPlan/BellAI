import Foundation
import UserNotifications

@main
struct RoutineNotificationChecks {
    @MainActor
    static func main() throws {
        let id = UUID()
        let routine = Routine(id: id, name: "Morning", time: "07:30", timezone: "America/Chicago",
                              actions: ["Open curtains", "Read agenda"])
        let request = try RoutineNotifications.request(for: routine)
        let trigger = request.trigger as! UNCalendarNotificationTrigger
        precondition(trigger.repeats)
        precondition(trigger.dateComponents.hour == 7 && trigger.dateComponents.minute == 30)
        precondition(trigger.dateComponents.timeZone?.identifier == "America/Chicago")
        precondition(trigger.nextTriggerDate() != nil)
        precondition(request.content.title == "Morning")
        precondition(request.content.body == "Open curtains • Read agenda")
        precondition(request.content.sound != nil)
        precondition(request.identifier == "routine." + id.uuidString.lowercased())
        let changed = Routine(id: id, name: "Updated", time: "23:59", timezone: "Asia/Tokyo", actions: ["Rest"])
        let changedRequest = try RoutineNotifications.request(for: changed)
        precondition(changedRequest.identifier == request.identifier)
        for (time, zone) in [("24:00", "America/Chicago"), ("07:60", "America/Chicago"), ("bad", "UTC"), ("07:30", "Invalid/Zone")] {
            do {
                _ = try RoutineNotifications.request(for: Routine(id: id, name: "Invalid", time: time, timezone: zone, actions: []))
                preconditionFailure("Invalid schedule accepted")
            } catch {}
        }
        print("Routine notification checks passed")
    }
}
