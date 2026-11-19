import SwiftUI

struct HomeHeaderView: View {
    var firstName = ""
    var lastName = ""

    private var welcomeMessage: String {
        firstName.isEmpty ? "Good morning" : "Good morning, \(firstName)"
    }

    var body: some View {
        Text(welcomeMessage)
            .font(.title.weight(.bold))
            .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HomeHeaderView()
        .padding(20)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
