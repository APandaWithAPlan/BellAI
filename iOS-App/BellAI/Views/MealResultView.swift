import SwiftUI

// what BellAI made of a meal photo, over whatever screen the photo came from
struct MealResultView: View {
    var model: MealPhotoViewModel
    @State private var showsEditor = false
    @State private var calories = ""
    @State private var protein = ""
    @State private var problem: String?

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)
    private let green = Color(red: 0.10, green: 0.67, blue: 0.43)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meal")
                    .font(.headline)
                    .foregroundStyle(ink)
                Spacer()
                Button("Done") { model.dismiss() }
                    .font(.headline)
                    .foregroundStyle(accent)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.phase {
                    case .idle, .analyzing:
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Analyzing your meal…").foregroundStyle(muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    case .failed(let message):
                        Label("Couldn't analyze that", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundStyle(accent)
                        Text(message).foregroundStyle(ink)
                    case .result(let meal):
                        result(meal)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .presentationDetents([.medium, .large])
        .alert("Edit meal", isPresented: $showsEditor) {
            TextField("Calories", text: $calories)
                .keyboardType(.numberPad)
            TextField("Protein (g)", text: $protein)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Save and log") { saveEdit() }
        } message: {
            Text("Correct the estimate if it looks off. Saving logs the meal to Apple Health.")
        }
    }

    @ViewBuilder
    private func result(_ meal: MealResult) -> some View {
        Text(meal.summary)
            .font(.body)
            .lineSpacing(4)
            .foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)

        if let nutrition = meal.current {
            HStack(spacing: 12) {
                tile("Calories", value: "\(nutrition.calories)", unit: "kcal", symbol: "flame")
                tile("Protein", value: "\(nutrition.proteinGrams)", unit: "g", symbol: "fish")
            }
            if meal.isEdited, let reported = meal.reported {
                Text("Edited · was \(reported.calories) kcal and \(reported.proteinGrams) g protein")
                    .font(.caption)
                    .foregroundStyle(muted)
            }

            if meal.isLogged {
                Label("Logged to Apple Health", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(green)
            } else {
                HStack(spacing: 8) {
                    Button { openEditor(nutrition) } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button { Task { await model.log() } } label: {
                        Text(model.isLogging ? "Logging…" : "Log meal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isLogging)
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            if let logError = model.logError {
                Text(logError).font(.caption).foregroundStyle(.red)
            }
        } else {
            Text("There is nothing to log without calories.")
                .font(.subheadline)
                .foregroundStyle(muted)
        }
    }

    private func tile(_ title: String, value: String, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(ink)
            Text("\(title) · \(unit)")
                .font(.caption)
                .foregroundStyle(muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func openEditor(_ nutrition: Nutrition) {
        calories = String(nutrition.calories)
        protein = String(nutrition.proteinGrams)
        problem = nil
        showsEditor = true
    }

    private func saveEdit() {
        let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespaces) }
        guard let calories = Int(trimmed(calories)), let protein = Int(trimmed(protein)) else {
            problem = "Enter whole numbers for calories and protein."
            return
        }
        problem = nil
        Task {
            if !(await model.correctAndLog(Nutrition(calories: calories, proteinGrams: protein))) {
                problem = "Calories can be 1 to 10,000 and protein 0 to 1,000 g."
            }
        }
    }
}
