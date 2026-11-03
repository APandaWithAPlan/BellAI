import SwiftUI

struct HomeFeatureCardsView: View {
    var tasks: TasksViewModel
    var mail: MailViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            grid
            NavigationLink {
                MailView(model: mail)
                    #if os(iOS)
                    .toolbar(.visible, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            } label: {
                MailCardView(detail: mail.cardDetail, needsAttention: !mail.important.isEmpty || !mail.drafts.isEmpty)
            }
            .buttonStyle(.plain)
        }
    }

    private var grid: some View {
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

// one wide row under the cards, it has more to say than a card has room for
private struct MailCardView: View {
    let detail: String
    let needsAttention: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.96))
                .accessibilityHidden(true)
            Text("Mail")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
            Spacer(minLength: 8)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(needsAttention ? Color(red: 1, green: 0.18, blue: 0.45) : Color(red: 0.48, green: 0.43, blue: 0.46))
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.48, green: 0.43, blue: 0.46))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color(red: 0.91, green: 0.88, blue: 0.90), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HomeFeatureCardsView(tasks: TasksViewModel(store: PlannerPreviewStore()), mail: MailViewModel(service: HTTPMailService()))
        .padding(20)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
