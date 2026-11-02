import SwiftUI

enum HomeSection: String, CaseIterable, Identifiable {
    case main = "Main"
    case agenda = "Agenda"

    var id: Self { self }
}

struct HomeSectionNavigationView: View {
    @Binding var selection: HomeSection
    var height: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HomeSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.rawValue)
                        .font(.subheadline)
                        .fontWeight(selection == section ? .semibold : .regular)
                        .foregroundStyle(selection == section
                            ? Color(red: 1, green: 0.18, blue: 0.45)
                            : Color(red: 0.48, green: 0.43, blue: 0.46))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.97, green: 0.96, blue: 0.97), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? [.isSelected] : [])
            }
        }
        .padding(4)
        .frame(maxWidth: 260)
        .frame(height: height)
        .background(Color(red: 0.90, green: 0.89, blue: 0.90), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Home navigation")
    }
}

#Preview {
    @Previewable @State var selection: HomeSection = .main
    HomeSectionNavigationView(selection: $selection, height: 56 * 2 / 3)
        .padding()
}
