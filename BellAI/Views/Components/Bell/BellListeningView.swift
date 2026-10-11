import SwiftUI

struct BellListeningView: View {
    private let accent = Color(red: 0.92, green: 0.24, blue: 0.49)
    private let barHeights: [CGFloat] = [14, 26, 36, 22, 42, 30, 20, 32, 16]

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.10))
                    .frame(width: 136, height: 136)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1, green: 0.43, blue: 0.63),
                                accent,
                                Color(red: 0.65, green: 0.12, blue: 0.34)
                            ],
                            center: UnitPoint(x: 0.4, y: 0.25),
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 96, height: 96)

                BellVoiceMark()
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 32, height: 34)
            }
            .accessibilityHidden(true)

            HStack(spacing: 5) {
                ForEach(barHeights.indices, id: \.self) { index in
                    Capsule()
                        .fill(accent.opacity(index == 4 ? 1 : 0.65))
                        .frame(width: 4, height: barHeights[index])
                }
            }
            .frame(height: 42)
            .accessibilityHidden(true)

            Text("Listening...")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BellVoiceMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: 0.06 * w, y: 0.55 * h))
        path.addQuadCurve(to: CGPoint(x: 0.16 * w, y: 0.45 * h), control: CGPoint(x: 0.16 * w, y: 0.55 * h))
        path.addLine(to: CGPoint(x: 0.16 * w, y: 0.28 * h))
        path.addCurve(to: CGPoint(x: 0.34 * w, y: 0.28 * h), control1: CGPoint(x: 0.16 * w, y: 0.12 * h), control2: CGPoint(x: 0.34 * w, y: 0.12 * h))
        path.addLine(to: CGPoint(x: 0.34 * w, y: 0.82 * h))
        path.addCurve(to: CGPoint(x: 0.52 * w, y: 0.82 * h), control1: CGPoint(x: 0.34 * w, y: 0.98 * h), control2: CGPoint(x: 0.52 * w, y: 0.98 * h))
        path.addLine(to: CGPoint(x: 0.52 * w, y: 0.16 * h))
        path.addCurve(to: CGPoint(x: 0.70 * w, y: 0.16 * h), control1: CGPoint(x: 0.52 * w, y: 0), control2: CGPoint(x: 0.70 * w, y: 0))
        path.addLine(to: CGPoint(x: 0.70 * w, y: 0.68 * h))
        path.addCurve(to: CGPoint(x: 0.88 * w, y: 0.68 * h), control1: CGPoint(x: 0.70 * w, y: 0.84 * h), control2: CGPoint(x: 0.88 * w, y: 0.84 * h))
        path.addLine(to: CGPoint(x: 0.88 * w, y: 0.52 * h))
        path.addQuadCurve(to: CGPoint(x: 0.97 * w, y: 0.45 * h), control: CGPoint(x: 0.88 * w, y: 0.45 * h))
        return path
    }
}

#Preview {
    BellListeningView()
        .padding(20)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
