#if DEBUG
import Foundation

// made up days of eating for trying the recommendations without logging real meals: one that is low on protein, one with
// too much sodium and one that is on track. they match the scenarios the Insights server is tested with
enum SampleDay: String, CaseIterable, Identifiable {
    case lowProtein = "Low protein"
    case highSodium = "High sodium"
    case onTrack = "On track"

    var id: Self { self }

    var meals: [LoggedMeal] {
        let rows: [(String, Double, Double, Double, Double, Double, Double, Double)] // name, kcal, protein, carbs, fat, fiber, sugar, sodium
        switch self {
        case .lowProtein:
            rows = [("Toast with jam", 420, 8, 80, 6, 4, 25, 450), ("Pasta marinara", 700, 18, 120, 12, 8, 15, 800),
                    ("Apple and a granola bar", 330, 5, 60, 8, 6, 25, 150)]
        case .highSodium:
            rows = [("Instant ramen", 600, 22, 80, 20, 3, 5, 1_900), ("Deli sandwich and chips", 700, 35, 70, 30, 5, 8, 1_700),
                    ("Grilled chicken and vegetables", 600, 55, 30, 20, 12, 8, 700)]
        case .onTrack:
            rows = [("Oatmeal with berries", 350, 12, 60, 7, 9, 14, 120), ("Chicken burrito bowl", 650, 45, 70, 18, 13, 6, 1_000),
                    ("Salmon, rice and broccoli", 600, 40, 55, 22, 6, 4, 500), ("Yogurt and almonds", 300, 22, 15, 16, 3, 9, 100)]
        }
        return rows.map { name, kcal, protein, carbs, fat, fiber, sugar, sodium in
            LoggedMeal(date: .now, name: name, nutrients: MealNutrients(
                kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat, fiberG: fiber, sugarG: sugar, sodiumMg: sodium))
        }
    }
}
#endif
