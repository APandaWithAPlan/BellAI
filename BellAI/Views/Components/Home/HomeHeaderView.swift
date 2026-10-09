import SwiftUI

struct HomeHeaderView: View {
    var welcomeMessage = "Good morning, Maya"
    var subtitle = "Home is calm · 2 things need you"
    var avatarInitials = "MK"

    @ScaledMetric(relativeTo: .body) private var avatarSize = 44.0

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(welcomeMessage)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color(red: 0.10, green: 0.71, blue: 0.43))
                        .accessibilityHidden(true)

                    Text(subtitle)
                        .foregroundStyle(Color(red: 0.48, green: 0.43, blue: 0.46))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(avatarInitials)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 0.88, green: 0.12, blue: 0.37))
                .frame(width: avatarSize, height: avatarSize)
                .background(Color(red: 1, green: 0.91, blue: 0.94), in: Circle())
                .accessibilityLabel("Profile, \(avatarInitials)")
        }
    }
}

#Preview {
    HomeHeaderView()
        .padding(20)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
