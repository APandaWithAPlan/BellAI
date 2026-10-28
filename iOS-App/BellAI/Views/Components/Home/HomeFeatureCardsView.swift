import SwiftUI

struct HomeFeatureCardsView: View {
    var tasks: TasksViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            NavigationLink {
                SmartHomeView()
            } label: {
                FeatureCardView(
                    title: "Lights", detail: "Connect", symbol: "lightbulb",
                    tint: Color(red: 1, green: 0.57, blue: 0.16)
                )
            }
            .buttonStyle(.plain)
            NavigationLink {
                SmartHomeView()
            } label: {
                FeatureCardView(
                    title: "Climate", detail: "Connect", symbol: "thermometer.medium",
                    tint: Color(red: 0.28, green: 0.51, blue: 1)
                )
            }
            .buttonStyle(.plain)
            NavigationLink {
                PlannerView(model: tasks)
                    #if os(iOS)
                    .toolbar(.visible, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            } label: {
                FeatureCardView(
                    title: "Plan", detail: tasks.isLoaded ? "\(tasks.tasks.count) tasks" : "Loading…", symbol: "checklist",
                    tint: Color(red: 0.10, green: 0.71, blue: 0.43)
                )
            }
            .buttonStyle(.plain)
            NavigationLink {
                SecurityView()
            } label: {
                FeatureCardView(
                    title: "Security", detail: "Home", symbol: "checkmark.shield",
                    tint: Color(red: 1, green: 0.18, blue: 0.45)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    HomeFeatureCardsView(tasks: TasksViewModel(store: PlannerPreviewStore()))
        .padding(20)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
