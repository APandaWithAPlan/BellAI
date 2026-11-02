import SwiftUI

struct SmartHomeView: View {
    @State private var showsConnectionOptions = false

    private let background = Color(red: 0.97, green: 0.96, blue: 0.97)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)
    private let accent = Color(red: 0.94, green: 0.23, blue: 0.49)

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Text("My home")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ink)
                Spacer(minLength: 0)
                Button { showsConnectionOptions = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 23, weight: .light))
                        .foregroundStyle(ink)
                        .frame(width: 48, height: 48)
                        .background(.white, in: Circle())
                        .overlay(Circle().strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Connect a home device")
            }

            Spacer(minLength: 24)
            VStack(spacing: 12) {
                Image(systemName: "house")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text("No devices connected")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ink)
                Text("Tap + to explore ways to connect your home devices.")
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .preferredColorScheme(.light)
        .tint(accent)
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        #endif
        .sheet(isPresented: $showsConnectionOptions) {
            HomeDeviceConnectionOptionsView()
                .preferredColorScheme(.light)
        }
    }
}

private enum HomeDeviceConnectionOption: String, CaseIterable, Identifiable {
    case appleHome, matter, manufacturer

    var id: Self { self }

    var title: String {
        switch self {
        case .appleHome: "Apple Home"
        case .matter: "Matter device"
        case .manufacturer: "Device maker’s app"
        }
    }

    var symbol: String {
        switch self {
        case .appleHome: "house"
        case .matter: "qrcode.viewfinder"
        case .manufacturer: "apps.iphone"
        }
    }

    var subtitle: String {
        switch self {
        case .appleHome: "Lights, thermostats, and Home-compatible accessories"
        case .matter: "Accessories with a Matter setup code"
        case .manufacturer: "Other smart home devices"
        }
    }

    var instructions: String {
        switch self {
        case .appleHome:
            "Open Apple’s Home app, tap +, then choose Add Accessory. Follow the accessory’s setup instructions to add it to your home."
        case .matter:
            "Put your accessory into pairing mode using its instructions. In Apple’s Home app, tap +, choose Add Accessory, and scan the Matter setup code. Some devices require a compatible home hub."
        case .manufacturer:
            "Use the app recommended by your device’s manufacturer to pair the device and complete its network setup. Check its instructions for Apple Home or Matter compatibility."
        }
    }
}

private struct HomeDeviceConnectionOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    private let accent = Color(red: 0.94, green: 0.23, blue: 0.49)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(HomeDeviceConnectionOption.allCases) { option in
                        NavigationLink {
                            VStack(alignment: .leading, spacing: 20) {
                                Image(systemName: option.symbol)
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundStyle(accent)
                                    .accessibilityHidden(true)
                                Text(option.instructions)
                                    .font(.body)
                                Text("Pairing in another app won’t add device controls to BellAI yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(24)
                            .navigationTitle(option.title)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: option.symbol)
                                    .font(.title2.weight(.light))
                                    .foregroundStyle(accent)
                                    .frame(width: 32)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title).font(.headline)
                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                } footer: {
                    Text("Choose an option for setup instructions. Direct device pairing and controls in BellAI are not available yet.")
                }
            }
            .navigationTitle("Connect a device")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(accent)
        }
    }
}

#Preview {
    NavigationStack { SmartHomeView() }
}
