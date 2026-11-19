import SwiftUI
import CoreLocation
import Observation
#if os(iOS)
import UIKit
#endif

/// Settings layout with a location control backed by system authorization.
struct SettingsView: View {
    var profile: ProfileViewModel? = nil
    var recorder: RecorderReceiver? = nil
    var onServerSaved: () -> Void = {}
    @State private var showsAccountDetails = false
    @State private var serverHost = ""
    @State private var serverPorts: [ServerSettings.Service: String] = [:]
    @State private var serverError: String?
    @State private var serverResults: [ServerSettings.Service: Bool] = [:]
    @State private var routineServerResult: Bool?
    @State private var isTestingServer = false
    @State private var wifiSetup = RecorderWifiSetup()
    @State private var wifiName = ""
    @State private var wifiPassword = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var locationPermission = SettingsLocationPermission()
    @State private var showsLocationSettings = false
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
                privacyCard
                serverCard
                if let recorder { recorderCard(recorder) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surface)
        .sheet(isPresented: $showsAccountDetails) {
            if let profile { AccountDetailsView(model: profile) }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await locationPermission.refresh() }
        }
        .onAppear(perform: loadServerFields)
        .onDisappear { wifiSetup.cancel() }
        .alert("Location access", isPresented: $showsLocationSettings) {
            #if os(iOS)
            Button("Open Settings") { openLocationSettings() }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text("Change BellAI’s location access in System Settings. If Location Services are disabled for your device, enable them under Privacy & Security → Location Services first.")
        }
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
            Button { showsAccountDetails = true } label: {
                Image(systemName: "person")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ink)
                    .frame(width: 48, height: 48)
                    .background(.white, in: Circle())
                    .overlay(Circle().strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
            }
            .buttonStyle(.plain)
            .disabled(profile == nil)
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

                locationTile
            }
        }
    }

    private var serverCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                    Text("Server options")
                        .font(.headline)
                        .foregroundStyle(ink)
                    Spacer(minLength: 0)
                }

                Text("Where BellAI finds your Mac. ai-server is its name on Tailscale. On NetBird or your local network, enter the Mac's IP address instead. iOS only allows plain HTTP to IP addresses, short names and .local names.")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Address")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(muted)
                    serverField("ai-server", text: $serverHost, keyboard: .URL)
                }

                HStack(alignment: .top, spacing: 8) {
                    ForEach(ServerSettings.Service.allCases, id: \.self) { service in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(service.title) port")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(muted)
                            serverField("\(service.defaultPort)", text: portBinding(service), keyboard: .numberPad)
                        }
                    }
                }

                if let serverError {
                    Text(serverError).font(.caption).foregroundStyle(.red)
                }
                ForEach(ServerSettings.Service.allCases, id: \.self) { service in
                    if let reached = serverResults[service] {
                        serverStatus(service.title, reached: reached)
                    }
                }
                if let reached = routineServerResult {
                    serverStatus("Routine", reached: reached)
                }

                HStack(spacing: 8) {
                    Button(action: saveServer) {
                        Text(isTestingServer ? "Testing…" : "Save and test")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(accent, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isTestingServer)
                    Button(action: resetServer) {
                        Text("Reset")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(minWidth: 72, minHeight: 44)
                            .background(surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isTestingServer)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func recorderCard(_ recorder: RecorderReceiver) -> some View {
        @Bindable var recorder = recorder
        return card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                    Text("Clip-on recorder")
                        .font(.headline)
                        .foregroundStyle(ink)
                    Spacer(minLength: 0)
                    Toggle("Receive recordings", isOn: $recorder.isEnabled)
                        .labelsHidden()
                        .tint(accent)
                }

                Text("The Pico recorder finds this phone on your Wi-Fi and uploads its finished files here, then deletes them from its SD card. It can only upload while BellAI is open. Recordings are saved in the Files app under BellAI.")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(muted)
                    serverField(RecorderReceiver.defaultToken, text: $recorder.token, keyboard: .default)
                    Text("Must match AUTH_TOKEN in the recorder's config.h.")
                        .font(.caption2)
                        .foregroundStyle(muted)
                }

                switch recorder.status {
                case .off:
                    Label("Off", systemImage: "moon.zzz")
                        .font(.caption)
                        .foregroundStyle(muted)
                case .listening:
                    Label("Waiting for the recorder on port \(String(recorder.boundPort ?? RecorderReceiver.defaultPort))", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(green)
                case .failed(let message):
                    Label("Couldn't start: \(message)", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text(recorder.lastFile.map { "\(recorder.recordingCount) saved, latest \($0)" } ?? "\(recorder.recordingCount) saved")
                    .font(.caption)
                    .foregroundStyle(muted)

                Divider()
                wifiSetupSection(token: recorder.token)
            }
        }
    }

    // sends the Wi-Fi network the recorder uploads through, over Bluetooth
    private func wifiSetupSection(token: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recorder's Wi-Fi")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
            Text("Unplug the recorder and plug it in again, then send the network it should upload through, within 15 seconds. Tap Send first, then plug it in. It needs a 2.4 GHz network, and this phone must be on the same one to receive.")
                .font(.caption)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Wi-Fi network name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(muted)
                serverField("The name you pick on your phone's Wi-Fi list", text: $wifiName, keyboard: .default)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(muted.opacity(0.35)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Wi-Fi network password")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(muted)
                SecureField("The password for that network", text: $wifiPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .foregroundStyle(ink)
                    .padding(10)
                    .frame(minHeight: 44)
                    .background(surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(muted.opacity(0.35)))
                Text("Leave empty only if the network has no password.")
                    .font(.caption2)
                    .foregroundStyle(muted)
            }
            switch wifiSetup.phase {
            case .idle:
                EmptyView()
            case .searching:
                Label("Looking for the recorder…", systemImage: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(muted)
            case .connecting:
                Label("Connecting…", systemImage: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(muted)
            case .sending:
                Label("Sending…", systemImage: "arrow.up.circle").font(.caption).foregroundStyle(muted)
            case .done:
                Label("Saved on the recorder. It uses this network from its next upload.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(green)
            case .failed(let error):
                Label(error.localizedDescription, systemImage: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
            }
            Button {
                wifiSetup.send(token: token, ssid: wifiName, password: wifiPassword)
            } label: {
                Text(wifiSetup.isBusy ? "Working…" : "Send to recorder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(wifiSetup.isBusy)
        }
    }

    private func serverStatus(_ title: String, reached: Bool) -> some View {
        Label("\(title): \(reached ? "connected" : "couldn't connect")",
              systemImage: reached ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.caption)
            .foregroundStyle(reached ? green : .red)
    }

    private func serverField(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.subheadline)
            .foregroundStyle(ink)
            .padding(10)
            .frame(minHeight: 44)
            .background(surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func portBinding(_ service: ServerSettings.Service) -> Binding<String> {
        Binding(get: { serverPorts[service] ?? "" }, set: { serverPorts[service] = $0 })
    }

    // what is in use now, so the form starts from it
    private func loadServerFields() {
        serverHost = ServerSettings.resolved(.chat).host
        for service in ServerSettings.Service.allCases {
            serverPorts[service] = String(ServerSettings.resolved(service).port)
        }
    }

    private func saveServer() {
        serverError = nil
        serverResults = [:]
        routineServerResult = nil
        var ports: [ServerSettings.Service: Int] = [:]
        for service in ServerSettings.Service.allCases {
            let text = (serverPorts[service] ?? "").trimmingCharacters(in: .whitespaces)
            guard let port = text.isEmpty ? service.defaultPort : Int(text) else {
                serverError = "\(service.title) needs a port between 1 and 65535."
                return
            }
            ports[service] = port
        }
        if let problem = ServerSettings.save(host: serverHost, ports: ports) {
            serverError = problem
            return
        }
        loadServerFields()
        onServerSaved()
        isTestingServer = true
        Task {
            async let routineCheck = checkRoutineServer()
            var results: [ServerSettings.Service: Bool] = [:]
            for service in ServerSettings.Service.allCases {
                results[service] = await ServerSettings.isReachable(service)
            }
            serverResults = results
            routineServerResult = await routineCheck
            isTestingServer = false
        }
    }

    private func checkRoutineServer() async -> Bool {
        // Use the actual routines endpoint: /health can succeed on older servers
        // that do not support routines or cannot read their stored data.
        do {
            _ = try await HTTPRoutineService().load()
            return true
        } catch {
            return false
        }
    }

    private func resetServer() {
        ServerSettings.reset()
        serverError = nil
        serverResults = [:]
        routineServerResult = nil
        loadServerFields()
        onServerSaved()
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
            statusSwitch(isOn: isOn)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(isOn ? "on" : "off"), display only")
    }

    private func statusSwitch(isOn: Bool) -> some View {
        Capsule()
            .fill(isOn ? accent : muted.opacity(0.25))
            .frame(width: 44, height: 28)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 22, height: 22).padding(3)
            }
            .accessibilityHidden(true)
    }

    private var locationTile: some View {
        Button(action: changeLocationAccess) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(accent)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("Location")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                statusSwitch(isOn: locationPermission.isEnabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Location")
        .accessibilityValue(locationPermission.isEnabled ? "On" : "Off")
        .accessibilityHint(locationPermission.isEnabled
            ? "Opens Settings to turn off location access"
            : "Requests location access or opens Settings to enable it")
    }

    private func changeLocationAccess() {
        Task {
            await locationPermission.refresh()
            if locationPermission.requestAccessIfNeeded() { return }
            if !locationPermission.servicesEnabled {
                showsLocationSettings = true
            } else {
                openLocationSettings()
            }
        }
    }

    private func openLocationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url) { opened in
                if !opened { showsLocationSettings = true }
            }
        }
        #else
        showsLocationSettings = true
        #endif
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

@MainActor
@Observable
private final class SettingsLocationPermission: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var isEnabled = false
    private(set) var servicesEnabled = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func refresh() async {
        // Check the global setting off the main thread; no location request is needed.
        servicesEnabled = await Task.detached {
            CLLocationManager.locationServicesEnabled()
        }.value
        let status = manager.authorizationStatus
        isEnabled = servicesEnabled && (status == .authorizedAlways || status == .authorizedWhenInUse)
    }

    func requestAccessIfNeeded() -> Bool {
        guard servicesEnabled, manager.authorizationStatus == .notDetermined else { return false }
        manager.requestWhenInUseAuthorization()
        return true
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { await refresh() }
    }
}

#Preview {
    SettingsView()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavigationView(selection: .constant(.settings))
        }
}
