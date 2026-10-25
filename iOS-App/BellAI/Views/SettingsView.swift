import SwiftUI

/// Settings layout; preference controls are display-only until their services are connected.
struct SettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)
    private let surface = Color(red: 0.97, green: 0.96, blue: 0.97)
    private let green = Color(red: 0.10, green: 0.67, blue: 0.43)

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                appearanceCard
                privacyCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surface)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MAKE BELL YOURS")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Text("Settings")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ink)
            }
            Spacer(minLength: 0)
            Image(systemName: "person")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(ink)
                .frame(width: 48, height: 48)
                .background(.white, in: Circle())
                .overlay(Circle().strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
                .accessibilityLabel("Profile")
        }
        .padding(.bottom, 2)
    }

    private var appearanceCard: some View {
        card {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    appearanceLabel
                    Spacer(minLength: 0)
                    appearanceSelector
                }
                VStack(alignment: .leading, spacing: 12) {
                    appearanceLabel
                    appearanceSelector
                }
            }
        }
    }

    private var appearanceLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Appearance").font(.headline).foregroundStyle(ink)
                Text("Light mode").font(.caption).foregroundStyle(muted)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var appearanceSelector: some View {
        HStack(spacing: 2) {
            Image(systemName: "sun.max")
                .foregroundStyle(accent)
                .frame(width: 36, height: 32)
                .background(.white, in: Capsule())
            Image(systemName: "moon")
                .foregroundStyle(muted)
                .frame(width: 36, height: 32)
        }
        .font(.system(size: 17, weight: .light))
        .padding(4)
        .background(surface, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Appearance: light mode")
    }

    private var privacyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(green)
                        .accessibilityHidden(true)
                    Text("Privacy & data")
                        .font(.headline)
                        .foregroundStyle(ink)
                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    preferenceTile("Local processing", symbol: "cpu", isOn: false)
                    preferenceTile("Secure storage", symbol: "lock.shield", isOn: true)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    permissionTile("Location", subtitle: "While using", symbol: "mappin.and.ellipse")
                    permissionTile("Email", subtitle: "Not connected", symbol: "envelope")
                    permissionTile("Music", subtitle: "Not connected", symbol: "music.note")
                    permissionTile("Calendar", subtitle: "Not connected", symbol: "calendar")
                    permissionTile("Health", subtitle: "Not connected", symbol: "heart.text.square")
                    permissionTile("Camera", subtitle: "Not connected", symbol: "camera")
                }
            }
        }
    }

    private func preferenceTile(_ title: String, symbol: String, isOn: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(green)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            // Display-only switch, so no privacy setting is changed by this layout.
            Capsule()
                .fill(isOn ? accent : muted.opacity(0.25))
                .frame(width: 44, height: 28)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 22, height: 22).padding(3)
                }
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(isOn ? "on" : "off"), display only")
    }

    private func permissionTile(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(ink)
                Text(subtitle).font(.caption2).foregroundStyle(muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Circle()
                .fill(muted.opacity(0.4))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90), lineWidth: 0.75)
            }
            .shadow(color: ink.opacity(0.05), radius: 14, y: 7)
    }
}

#Preview {
    SettingsView()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavigationView(selection: .constant(.settings))
        }
}
