import Foundation

// what the recommendations have to respect. kept on this phone, and sent with each request to the Insights server,
// which removes any suggestion that breaks them
struct FoodPreferences: Equatable, Codable {
    var calorieGoal: Int?
    var proteinGoalGrams: Int?
    var sodiumLimitMg: Int?
    var diet = "" // empty means no particular diet
    var goal = ""
    var fitnessLevel = ""
    var allergies: [String] = []
    var injuries: [String] = []
    var dislikes: [String] = []

    static let diets = ["vegetarian", "pescatarian", "vegan", "halal", "kosher"]
    static let goals = ["lose", "maintain", "gain"]
    static let fitnessLevels = ["beginner", "intermediate", "advanced"]

    // the most the server takes in each list
    static let allergyLimit = 20
    static let injuryLimit = 10
    static let dislikeLimit = 30

    // "peanuts, shellfish" -> ["peanuts", "shellfish"]
    static func list(from text: String, limit: Int) -> [String] {
        var seen = Set<String>()
        var items: [String] = []
        for piece in text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" }) {
            let item = String(piece.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(40))
            if !item.isEmpty, seen.insert(item).inserted { items.append(item) }
        }
        return Array(items.prefix(limit))
    }

    // what is wrong with these, or nil if the server will take them. the ranges are the server's
    var problem: String? {
        if let calorieGoal, !(800...6_000).contains(calorieGoal) { return "A calorie goal is between 800 and 6,000." }
        if let proteinGoalGrams, !(10...400).contains(proteinGoalGrams) { return "A protein goal is between 10 and 400 grams." }
        if let sodiumLimitMg, !(500...10_000).contains(sodiumLimitMg) { return "A sodium limit is between 500 and 10,000 mg." }
        if allergies.count > Self.allergyLimit || injuries.count > Self.injuryLimit || dislikes.count > Self.dislikeLimit {
            return "That's more allergies, injuries or dislikes than can be used. Keep the most important ones."
        }
        return nil
    }

    // the user part of an /insights request, leaving out what isn't set so the server's defaults apply
    var requestFields: [String: Any] {
        var fields: [String: Any] = [:]
        if let calorieGoal { fields["calorie_goal"] = calorieGoal }
        if let proteinGoalGrams { fields["protein_goal_g"] = proteinGoalGrams }
        if let sodiumLimitMg { fields["sodium_limit_mg"] = sodiumLimitMg }
        if !diet.isEmpty { fields["diet"] = diet }
        if !goal.isEmpty { fields["goal"] = goal }
        if !fitnessLevel.isEmpty { fields["fitness_level"] = fitnessLevel }
        if !allergies.isEmpty { fields["allergies"] = allergies }
        if !injuries.isEmpty { fields["injuries"] = injuries }
        if !dislikes.isEmpty { fields["dislikes"] = dislikes }
        return fields
    }
}

enum FoodPreferencesStore {
    private static let key = "food.preferences"

    static func load(defaults: UserDefaults = .standard) -> FoodPreferences {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(FoodPreferences.self, from: $0) } ?? FoodPreferences()
    }

    static func save(_ preferences: FoodPreferences, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: key) }
    }
}
