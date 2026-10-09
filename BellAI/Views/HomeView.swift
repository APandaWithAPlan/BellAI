import SwiftUI

struct HomeView: View {
    var body: some View {
        ScrollView {
            HomeHeaderView()
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HomeView()
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
