import SwiftUI

// what the recommendations have to respect: daily targets, diet, allergies and injuries
struct FoodPreferencesView: View {
    var model: InsightsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var calories: String
    @State private var protein: String
    @State private var sodium: String
    @State private var diet: String
    @State private var goal: String
    @State private var level: String
    @State private var allergies: String
    @State private var dislikes: String
    @State private var injuries: String
    @State private var problem: String?

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)

    init(model: InsightsViewModel) {
        self.model = model
        let current = model.preferences
        _calories = State(initialValue: current.calorieGoal.map(String.init) ?? "")
        _protein = State(initialValue: current.proteinGoalGrams.map(String.init) ?? "")
        _sodium = State(initialValue: current.sodiumLimitMg.map(String.init) ?? "")
        _diet = State(initialValue: current.diet)
        _goal = State(initialValue: current.goal)
        _level = State(initialValue: current.fitnessLevel)
        _allergies = State(initialValue: current.allergies.joined(separator: ", "))
        _dislikes = State(initialValue: current.dislikes.joined(separator: ", "))
        _injuries = State(initialValue: current.injuries.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(muted)
                Spacer()
                Text("Preferences").font(.headline).foregroundStyle(ink)
                Spacer()
                Button("Save", action: save)
                    .font(.headline)
            }
            .foregroundStyle(accent)
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Daily targets", note: "Leave one empty to use the usual: 2,000 calories, about 100 g of protein and 2,300 mg of sodium.") {
                        numberField("Calories", text: $calories)
                        numberField("Protein (g)", text: $protein)
                        numberField("Sodium limit (mg)", text: $sodium)
                    }
                    section("Eating", note: "Separate with commas. Nothing with an allergy, a disliked food or against your diet is suggested.") {
                        picker("Diet", selection: $diet, options: FoodPreferences.diets, none: "None")
                        picker("Goal", selection: $goal, options: FoodPreferences.goals, none: "Not set")
                        textField("Allergies, like peanuts, shellfish", text: $allergies)
                        textField("Foods you dislike", text: $dislikes)
                    }
                    section("Fitness", note: "Workouts that would strain an injury are left out. Try knee, ankle, back or shoulder.") {
                        picker("Fitness level", selection: $level, options: FoodPreferences.fitnessLevels, none: "Not set")
                        textField("Injuries", text: $injuries)
                    }
                    if let problem {
                        Text(problem).font(.footnote).foregroundStyle(accent)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
    }

    private func section<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(muted)
            VStack(spacing: 10, content: content)
                .modifier(WhiteCard())
            Text(note).font(.footnote).foregroundStyle(muted)
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(title).foregroundStyle(muted))
            .foregroundStyle(ink)
            .tint(accent)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
    }

    private func textField(_ title: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(title).foregroundStyle(muted))
            .foregroundStyle(ink)
            .tint(accent)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
    }

    private func picker(_ title: String, selection: Binding<String>, options: [String], none: String) -> some View {
        HStack {
            Text(title).foregroundStyle(ink)
            Spacer()
            Picker(title, selection: selection) {
                Text(none).tag("")
                ForEach(options, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(accent)
        }
    }

    private func save() {
        func number(_ text: String) -> Int?? { // nil is not a number, .some(nil) is empty
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? .some(nil) : Int(trimmed).map { .some($0) }
        }
        guard case .some(let calorieGoal) = number(calories), case .some(let proteinGoal) = number(protein),
              case .some(let sodiumLimit) = number(sodium) else {
            problem = "Targets need to be whole numbers."
            return
        }
        let preferences = FoodPreferences(
            calorieGoal: calorieGoal, proteinGoalGrams: proteinGoal, sodiumLimitMg: sodiumLimit,
            diet: diet, goal: goal, fitnessLevel: level,
            allergies: FoodPreferences.list(from: allergies, limit: FoodPreferences.allergyLimit),
            injuries: FoodPreferences.list(from: injuries, limit: FoodPreferences.injuryLimit),
            dislikes: FoodPreferences.list(from: dislikes, limit: FoodPreferences.dislikeLimit)
        )
        problem = model.save(preferences)
        if problem == nil { dismiss() }
    }
}
