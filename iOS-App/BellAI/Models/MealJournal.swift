import Foundation
import Observation

// a meal that was logged in the app, with what the food model found in it
struct LoggedMeal: Identifiable, Equatable, Codable {
    var id = UUID()
    var date: Date
    var name: String
    var nutrients: MealNutrients
}

// the meals logged in the app, kept on this phone for the recommendations. they are also logged to Apple Health,
// but that only holds calories and protein, and the recommendations need sodium, fiber and the rest too
@MainActor
@Observable
final class MealJournal {
    private static let key = "meals.journal"
    private static let keepDays = 14
    private static let keepMeals = 200

    private(set) var meals: [LoggedMeal]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        meals = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([LoggedMeal].self, from: $0) } ?? []
    }

    func add(name: String, nutrients: MealNutrients, now: Date = .now) {
        meals.append(LoggedMeal(date: now, name: String(name.prefix(200)), nutrients: nutrients))
        // old days are no use to a recommendation for today
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: now) ?? .distantPast
        meals = Array(meals.filter { $0.date >= cutoff }.suffix(Self.keepMeals))
        if let data = try? JSONEncoder().encode(meals) { defaults.set(data, forKey: Self.key) }
    }

    // oldest first
    func today(now: Date = .now) -> [LoggedMeal] {
        meals.filter { Calendar.current.isDate($0.date, inSameDayAs: now) }.sorted { $0.date < $1.date }
    }
}
