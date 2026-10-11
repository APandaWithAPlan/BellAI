import SwiftUI

struct BellMessageCardView<Actions: View>: View {
    enum Position {
        case leading, trailing
    }

    let position: Position
    let title: String
    let symbol: String
    var badge: String? = nil
    let message: String
    let subtext: String
    var onRoutineTap: (() -> Void)? = nil
    var isRoutineExpanded = false
    @ViewBuilder let actions: () -> Actions

    private let accent = Color(red: 0.92, green: 0.24, blue: 0.49)
    private let secondary = Color(red: 0.48, green: 0.43, blue: 0.46)

    var body: some View {
        Group {
            if position == .trailing {
                HStack(spacing: 0) {
                    Spacer(minLength: 52)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("“\(message)”")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtext)
                            .font(.caption2)
                            .foregroundStyle(secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Color(red: 0.94, green: 0.91, blue: 0.93),
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 20,
                            bottomLeadingRadius: 20,
                            bottomTrailingRadius: 5,
                            topTrailingRadius: 20
                        )
                    )
                    .contextMenu { actions() }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label(title, systemImage: symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)

                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(red: 0.07, green: 0.55, blue: 0.33))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.87, green: 0.97, blue: 0.92), in: Capsule())
                        }
                    }

                    Text(message)
                        .font(.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .contextMenu { actions() }

                    Button {
                        onRoutineTap?()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 17, weight: .light))
                                .foregroundStyle(accent)

                            Text(subtext)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: isRoutineExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .light))
                        }
                        .foregroundStyle(secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(minHeight: 56)
                        .background(Color(red: 0.95, green: 0.93, blue: 0.94), in: RoundedRectangle(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .strokeBorder(Color(red: 0.86, green: 0.82, blue: 0.85), lineWidth: 0.75)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(onRoutineTap == nil)
                    .accessibilityHint("Shows the routine used for this response")
                    .accessibilityValue(isRoutineExpanded ? "Expanded" : "Collapsed")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
    }
}
