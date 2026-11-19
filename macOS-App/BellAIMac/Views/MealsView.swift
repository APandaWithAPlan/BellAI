import AppKit
import SwiftUI
import UniformTypeIdentifiers

// a photo of a meal is analyzed, corrected if it is off, and kept in today's journal. recommendations come from the journal
struct MealsView: View {
    @Environment(Features.self) private var features
    @State private var note = ""
    @State private var problem: String?
    @State private var showPreferences = false

    var body: some View {
        let today = features.journal.today()
        let kcal = Int(today.map(\.nutrients.kcal).reduce(0, +).rounded())
        Page("Meals", subtitle: today.isEmpty ? nil : "\(today.count) logged today, about \(kcal) calories") {
            Button { showPreferences = true } label: { Image(systemName: "slider.horizontal.3") }
                .help("Food preferences")
        } content: {
            VStack(alignment: .leading, spacing: 24) {
                addMeal
                if !today.isEmpty { todayList(today) }
                RecommendationsSection()
            }
        }
        .sheet(isPresented: Binding(get: { features.meal.isShown }, set: { if !$0 { features.meal.dismiss() } })) {
            MealResultSheet()
        }
        .sheet(isPresented: $showPreferences) { PreferencesSheet() }
    }

    private var addMeal: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: $note, prompt: Text("What is it? (optional)"))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 20)).foregroundStyle(Theme.accent)
                Text("Drop a photo of your meal here")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose Photo…", action: choosePhoto)
                    .disabled(features.meal.isBusy)
            }
            if let problem { ProblemLine(text: problem) }
        }
        .padding(14)
        .panel()
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            analyze(url)
            return true
        }
    }

    private func todayList(_ meals: [LoggedMeal]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Rows(items: meals) { meal in
                HStack {
                    Text(meal.name).font(.system(size: 14)).lineLimit(1)
                    Spacer()
                    Text("\(Int(meal.nutrients.kcal.rounded())) cal  ·  \(Int(meal.nutrients.proteinG.rounded())) g protein")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a photo of your meal"
        if panel.runModal() == .OK, let url = panel.url { analyze(url) }
    }

    private func analyze(_ url: URL) {
        guard let jpeg = Self.jpeg(from: url) else {
            problem = "That doesn't look like a photo I can read."
            return
        }
        problem = nil
        if features.meal.begin(jpeg, note: note) { note = "" }
    }

    // the server takes up to 10 MB, and a meal is clear at 1600 pixels
    private static func jpeg(from url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
              var rep = NSBitmapImageRep(data: tiff) else { return nil }
        let longest = CGFloat(max(rep.pixelsWide, rep.pixelsHigh))
        if longest > 1_600 {
            let scale = 1_600 / longest
            let size = NSSize(width: CGFloat(rep.pixelsWide) * scale, height: CGFloat(rep.pixelsHigh) * scale)
            let small = NSImage(size: size)
            small.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: size))
            small.unlockFocus()
            guard let data = small.tiffRepresentation, let resized = NSBitmapImageRep(data: data) else { return nil }
            rep = resized
        }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}

private struct RecommendationsSection: View {
    @Environment(Features.self) private var features

    var body: some View {
        let model = features.insights
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recommendations").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(model.phase == .loading ? "Working…" : "Get Recommendations") { Task { await model.refresh() } }
                    .disabled(model.phase == .loading)
            }
            switch model.phase {
            case .idle:
                Text(model.mealCount == 0
                     ? "Log a meal first, or get ideas for the day from your preferences alone."
                     : "Ideas for food and exercise, from the \(model.mealCount) meal\(model.mealCount == 1 ? "" : "s") you logged today.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            case .loading:
                ProgressView().controlSize(.small)
            case .failed(let message):
                ProblemLine(text: message) { Task { await model.refresh() } }
            case .loaded(let insights):
                VStack(alignment: .leading, spacing: 16) {
                    Text(insights.summary).font(.system(size: 15))
                    if !insights.foods.isEmpty {
                        idea("Food") {
                            Rows(items: insights.foods) { food in
                                IdeaRow(title: food.title, detail: food.why,
                                        facts: [food.kcal.map { "\(Int($0.rounded())) cal" }, food.proteinG.map { "\(Int($0.rounded())) g protein" }])
                            }
                        }
                    }
                    if !insights.workouts.isEmpty {
                        idea("Exercise") {
                            Rows(items: insights.workouts) { workout in
                                IdeaRow(title: workout.title, detail: workout.why,
                                        facts: [workout.minutes.map { "\(Int($0.rounded())) min" }, workout.intensity])
                            }
                        }
                    }
                }
            }
        }
    }

    private func idea(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .semibold))
            content()
        }
    }
}

private struct IdeaRow: View {
    let title: String
    let detail: String
    let facts: [String?]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(facts.compactMap { $0 }.joined(separator: "  ·  ")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if !detail.isEmpty { Text(detail).font(.system(size: 13)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MealResultSheet: View {
    @Environment(Features.self) private var features
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var calories = 0
    @State private var protein = 0

    var body: some View {
        let model = features.meal
        VStack(alignment: .leading, spacing: 16) {
            switch model.phase {
            case .idle, .analyzing:
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Looking at your meal…") }
                    .frame(maxWidth: .infinity, minHeight: 80)
            case .failed(let message):
                ProblemLine(text: message)
            case .result(let meal):
                Text(meal.summary).font(.system(size: 15)).textSelection(.enabled)
                if let current = meal.current {
                    nutrition(current, meal: meal)
                } else {
                    Text("I couldn't find any food to work out calories for, so nothing can be logged.").foregroundStyle(.secondary)
                }
                if let error = model.logError { ProblemLine(text: error) }
                actions(meal)
            }
            if case .result = model.phase {} else {
                HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.background)
        .task { await model.analyzeStored() }
    }

    private func nutrition(_ current: Nutrition, meal: MealResult) -> some View {
        VStack(spacing: 0) {
            row("Calories", editing ? nil : "\(current.calories)")
            Divider()
            row("Protein", editing ? nil : "\(current.proteinGrams) g")
        }
        .overlay {
            if editing {
                VStack(spacing: 0) {
                    HStack { Text("Calories"); Spacer(); TextField("", value: $calories, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 90) }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                    Divider()
                    HStack { Text("Protein (g)"); Spacer(); TextField("", value: $protein, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 90) }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }
            }
        }
        .font(.system(size: 14))
        .panel()
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? " ").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder private func actions(_ meal: MealResult) -> some View {
        let model = features.meal
        HStack {
            if meal.isLogged {
                Label(meal.isEdited ? "Added with your correction" : "Added to today", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            if meal.current != nil && !meal.isLogged {
                if editing {
                    Button("Cancel") { editing = false }
                    Button("Save and Add") {
                        Task { if await model.correctAndLog(Nutrition(calories: calories, proteinGrams: protein)) { editing = false } }
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(!Nutrition(calories: calories, proteinGrams: protein).isValid || model.isLogging)
                } else {
                    Button("Edit") {
                        calories = meal.current?.calories ?? 0
                        protein = meal.current?.proteinGrams ?? 0
                        editing = true
                    }
                    Button("Add to Today") { Task { await model.log() } }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        .disabled(model.isLogging)
                }
            }
            Button(meal.isLogged ? "Done" : "Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }
}

private struct PreferencesSheet: View {
    @Environment(Features.self) private var features
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FoodPreferences()
    @State private var allergies = ""
    @State private var injuries = ""
    @State private var dislikes = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Food Preferences").font(.system(size: 17, weight: .semibold))
            Text("Recommendations stay within these. Anything that breaks them is removed before you see it.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Form {
                Section("Goals") {
                    TextField("Calories a day", value: $draft.calorieGoal, format: .number.grouping(.never))
                    TextField("Protein a day (g)", value: $draft.proteinGoalGrams, format: .number.grouping(.never))
                    TextField("Sodium limit (mg)", value: $draft.sodiumLimitMg, format: .number.grouping(.never))
                    Picker("Aim to", selection: $draft.goal) {
                        Text("No preference").tag("")
                        ForEach(FoodPreferences.goals, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Diet", selection: $draft.diet) {
                        Text("No particular diet").tag("")
                        ForEach(FoodPreferences.diets, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Fitness level", selection: $draft.fitnessLevel) {
                        Text("Not set").tag("")
                        ForEach(FoodPreferences.fitnessLevels, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                Section("Separate with commas") {
                    TextField("Allergies", text: $allergies)
                    TextField("Injuries", text: $injuries)
                    TextField("Dislikes", text: $dislikes)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            if let problem { ProblemLine(text: problem) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
        .background(Theme.background)
        .onAppear {
            draft = features.insights.preferences
            allergies = draft.allergies.joined(separator: ", ")
            injuries = draft.injuries.joined(separator: ", ")
            dislikes = draft.dislikes.joined(separator: ", ")
        }
    }

    private func save() {
        draft.allergies = FoodPreferences.list(from: allergies, limit: FoodPreferences.allergyLimit)
        draft.injuries = FoodPreferences.list(from: injuries, limit: FoodPreferences.injuryLimit)
        draft.dislikes = FoodPreferences.list(from: dislikes, limit: FoodPreferences.dislikeLimit)
        problem = features.insights.save(draft)
        if problem == nil { dismiss() }
    }
}
