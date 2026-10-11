import SwiftUI

struct FeatureCardView: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(tint)
                .frame(height: 18)
                .accessibilityHidden(true)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))

            Text(detail)
                .font(.caption2)
                .foregroundStyle(Color(red: 0.48, green: 0.43, blue: 0.46))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
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
    FeatureCardView(title: "Lights", detail: "8 on", symbol: "lightbulb", tint: .orange)
        .frame(width: 82)
        .padding()
}
