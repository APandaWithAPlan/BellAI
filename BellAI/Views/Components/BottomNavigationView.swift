import SwiftUI

enum BellAITab: String, CaseIterable, Identifiable {
    case home = "Home"
    case bell = "Bell"
    case activity = "Activity"
    case settings = "Settings"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .home: "house"
        case .bell: "sparkles"
        case .activity: "square.grid.2x2"
        case .settings: "gearshape"
        }
    }
}

struct BottomNavigationView: View {
    @Binding var selection: BellAITab
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .caption2) private var iconSize = 19.0

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let inactive = Color(red: 0.48, green: 0.43, blue: 0.46)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BellAITab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: iconSize, weight: .light))
                            .frame(height: iconSize + 2)
                            .accessibilityHidden(true)

                        Text(tab.rawValue)
                            .font(.caption2)
                            .fontWeight(selection == tab ? .semibold : .regular)
                    }
                    .foregroundStyle(selection == tab ? accent : inactive)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(Color.white.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 0.91, green: 0.88, blue: 0.90))
                .frame(height: 1 / displayScale)
        }
    }
}

#Preview {
    @Previewable @State var selection: BellAITab = .home

    Color(red: 0.97, green: 0.96, blue: 0.97)
        .ignoresSafeArea()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavigationView(selection: $selection)
        }
}
