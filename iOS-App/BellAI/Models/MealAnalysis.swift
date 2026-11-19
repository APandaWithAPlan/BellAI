import Foundation

// calories and protein, the two numbers a meal is logged with
struct Nutrition: Equatable {
    var calories: Int
    var proteinGrams: Int

    var isValid: Bool {
        (1...10_000).contains(calories) && (0...1_000).contains(proteinGrams)
    }
}

// everything the food model knows about a meal, which is what the recommendations are worked out from.
// the names are the ones the Insights server uses, so it is sent and saved as it is
struct MealNutrients: Equatable, Codable {
    var kcal = 0.0
    var proteinG = 0.0
    var carbsG = 0.0
    var fatG = 0.0
    var fiberG = 0.0
    var sugarG = 0.0
    var sodiumMg = 0.0

    private enum CodingKeys: String, CodingKey {
        case kcal
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case sodiumMg = "sodium_mg"
    }
}

// what the food model said about a photo. nutrition is nil when it found nothing to look it up with
struct MealAnalysis: Equatable {
    let summary: String
    let nutrition: Nutrition?
    var nutrients: MealNutrients? = nil
}

// a meal result on screen: what the model said, what the person says it should be, and whether it is logged
struct MealResult: Equatable {
    private let original: String
    private(set) var summary: String
    let reported: Nutrition?
    private(set) var current: Nutrition?
    private let nutrients: MealNutrients?
    var isLogged = false

    var isEdited: Bool { current != reported }

    init(_ analysis: MealAnalysis) {
        original = analysis.summary
        summary = analysis.summary
        reported = analysis.nutrition
        current = analysis.nutrition
        nutrients = analysis.nutrients
    }

    // what goes in the journal: everything the model found, with the calories and protein the person settled on
    var loggedNutrients: MealNutrients? {
        guard let current else { return nil }
        var all = nutrients ?? MealNutrients()
        all.kcal = Double(current.calories)
        all.proteinG = Double(current.proteinGrams)
        return all
    }

    // false if there is nothing to correct
    mutating func correct(to nutrition: Nutrition) -> Bool {
        guard let reported, nutrition.isValid else { return false }
        current = nutrition
        summary = Self.summary(original, from: reported, to: nutrition)
        return true
    }

    // the summary is written for the reported numbers, so a correction changes them in it
    static func summary(_ summary: String, from old: Nutrition, to new: Nutrition) -> String {
        let calories = "about \(old.calories) calories"
        let protein = "\(old.proteinGrams) g protein"
        guard summary.contains(calories), summary.contains(protein) else {
            return "\(summary) Corrected to \(new.calories) calories and \(new.proteinGrams) g protein."
        }
        return summary
            .replacingOccurrences(of: calories, with: "about \(new.calories) calories")
            .replacingOccurrences(of: protein, with: "\(new.proteinGrams) g protein")
    }
}
