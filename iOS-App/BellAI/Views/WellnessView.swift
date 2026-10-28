import SwiftUI

struct WellnessView: View {
    var isSubmitting = false
    var onSubmitPhoto: (Data, String) -> Bool
    @State private var health = WellnessHealthModel()
    @AppStorage("wellness.healthAccessRequested") private var hasRequestedAccess = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A BALANCED DAY").font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                        Text("Wellness").font(.largeTitle.weight(.bold)).foregroundStyle(ink)
                    }
                    Spacer()
                    Button(action: connectHealth) {
                        Image(systemName: "heart")
                            .font(.system(size: 22, weight: .light))
                            .frame(width: 48, height: 48)
                            .background(.white, in: Circle())
                            .overlay(Circle().strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ink)
                    .disabled(!health.isAvailable || health.isLoading)
                    .accessibilityLabel("Request Apple Health access")
                }

                healthAccess
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                         count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: 10) {
                    metric("steps", value: health.steps, symbol: "figure.walk", color: .blue)
                    metric("active kcal", value: health.activeCalories, symbol: "flame", color: .orange)
                    metric("water · mL", value: health.waterML, symbol: "drop", color: .green)
                }
                card {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Today’s workout").font(.title3.weight(.bold))
                        HStack(spacing: 14) {
                            Image(systemName: "dumbbell")
                                .font(.system(size: 25, weight: .light))
                                .foregroundStyle(.purple)
                                .frame(width: 56, height: 56)
                                .background(Color.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(health.workoutTitle ?? "No workout available").font(.headline)
                                Text(health.workoutMinutes.map { "\(Int($0.rounded())) min · Apple Health" } ?? "Workouts shared from Apple Health appear here.")
                                    .font(.subheadline).foregroundStyle(muted)
                            }
                        }
                    }
                }
                card {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Nutrition").font(.title3.weight(.bold))
                            Spacer()
                            PhotoPickerButton(isDisabled: isSubmitting, style: .logMeal, onPick: submitMeal)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text("\(formatted(health.dietaryCalories)) kcal logged")
                                Spacer()
                                Text("\(formatted(health.proteinGrams)) g protein").foregroundStyle(accent)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(formatted(health.dietaryCalories)) kcal logged")
                                Text("\(formatted(health.proteinGrams)) g protein").foregroundStyle(accent)
                            }
                        }
                        .font(.subheadline)
                        Text("Today’s entries shared from Apple Health. Meal photo analysis does not save nutrition to Health.")
                            .font(.caption).foregroundStyle(muted)
                    }
                }
                PhotoPickerButton(isDisabled: isSubmitting, style: .mealCard, onPick: submitMeal)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .foregroundStyle(ink)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .task(id: scenePhase) {
            if scenePhase == .active, hasRequestedAccess { await health.refresh() }
        }
        .refreshable { if hasRequestedAccess { await health.refresh() } }
        .alert("Apple Health", isPresented: Binding(get: { health.errorMessage != nil }, set: { if !$0 { health.errorMessage = nil } })) {
            Button("OK", role: .cancel) { health.errorMessage = nil }
        } message: {
            Text(health.errorMessage ?? "")
        }
    }

    private var healthAccess: some View {
        VStack(alignment: .leading, spacing: 8) {
            if health.isLoading {
                ProgressView("Reading Apple Health…").font(.subheadline)
            } else if !health.isAvailable {
                Text("Apple Health is unavailable on this device.")
            } else if !hasRequestedAccess {
                Button("Connect Apple Health", action: connectHealth)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
            } else {
                Text("Today · Apple Health").font(.subheadline.weight(.medium))
                Text("Missing values may mean no data is recorded or access isn’t shared. Manage access in the Health app.")
                    .font(.caption)
            }
        }
        .foregroundStyle(muted)
    }

    private func connectHealth() {
        Task {
            if await health.requestAccess() {
                hasRequestedAccess = true
                await health.refresh()
            }
        }
    }

    private func submitMeal(_ jpeg: Data) {
        _ = onSubmitPhoto(jpeg, "Help me understand this meal.")
    }

    private func formatted(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—"
    }

    private func metric(_ title: String, value: Double?, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text(formatted(value)).font(.title3.weight(.bold))
            Text(title).font(.caption).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
            .shadow(color: ink.opacity(0.05), radius: 14, y: 7)
    }
}
