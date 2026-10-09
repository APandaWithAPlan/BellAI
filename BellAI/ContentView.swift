import SwiftUI
import Playgrounds

struct ContentView: View {
    @State private var selectedTab: BellAITab = .home

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.97)
                .ignoresSafeArea()

            if selectedTab == .home {
                HomeView()
            } else {
                Text(selectedTab.rawValue)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavigationView(selection: $selectedTab)
        }
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
