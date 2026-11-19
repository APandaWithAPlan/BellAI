import SwiftUI

// food and workout ideas for today, on the Activity screen
struct RecommendationsCardView: View {
    var model: InsightsViewModel
    @State private var showsPreferences = false

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recommendations").font(.title3.weight(.bold))
                Spacer()
                Button { showsPreferences = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .light))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Food and fitness preferences")
            }
            .foregroundStyle(ink)

            content

            Text("Ideas skip your allergies, diet and injuries, and are not medical advice.")
                .font(.caption).foregroundStyle(muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
        .shadow(color: ink.opacity(0.05), radius: 14, y: 7)
        .sheet(isPresented: $showsPreferences) { FoodPreferencesView(model: model) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            Text(model.mealCount == 0
                 ? "Log a meal with a photo and BellAI will suggest what to eat and how to move next."
                 : "Based on the \(model.mealCount == 1 ? "meal" : "\(model.mealCount) meals") you logged today.")
                .font(.subheadline).foregroundStyle(muted)
            getButton("Get recommendations")
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Working out your day…").font(.subheadline).foregroundStyle(muted)
            }
        case .failed(let message):
            Text(message).font(.subheadline).foregroundStyle(accent)
            getButton("Try again")
        case .loaded(let insights):
            Text(insights.summary).font(.subheadline).foregroundStyle(ink)
            if !insights.foods.isEmpty {
                group("Eat", symbol: "fork.knife") {
                    ForEach(insights.foods) { food in
                        idea(food.title, detail: food.why, extra: foodExtra(food))
                    }
                }
            }
            if !insights.workouts.isEmpty {
                group("Move", symbol: "figure.walk") {
                    ForEach(insights.workouts) { workout in
                        idea(workout.title, detail: workout.why, extra: workoutExtra(workout))
                    }
                }
            }
            getButton("Refresh")
        }
        #if DEBUG
        sampleMenu
        #endif
    }

    #if DEBUG
    // for trying it without logging meals: asks about a made up day instead
    private var sampleMenu: some View {
        Menu("Try a sample day") {
            ForEach(SampleDay.allCases) { day in
                Button(day.rawValue) { Task { await model.refresh(sample: day.meals) } }
            }
        }
        .font(.footnote)
        .foregroundStyle(muted)
    }
    #endif

    private func getButton(_ title: String) -> some View {
        Button { Task { await model.refresh() } } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(accent, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func group<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accent)
            content()
        }
    }

    private func idea(_ title: String, detail: String, extra: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                Spacer(minLength: 8)
                if !extra.isEmpty { Text(extra).font(.caption).foregroundStyle(muted) }
            }
            if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(muted) }
        }
        .accessibilityElement(children: .combine)
    }

    private func foodExtra(_ food: Insights.Food) -> String {
        [food.kcal.map { "\(Int($0.rounded())) kcal" }, food.proteinG.map { "\(Int($0.rounded())) g protein" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func workoutExtra(_ workout: Insights.Workout) -> String {
        [workout.minutes.map { "\(Int($0.rounded())) min" }, workout.intensity].compactMap { $0 }.joined(separator: " · ")
    }
}
