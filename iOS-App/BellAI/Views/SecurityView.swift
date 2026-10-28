import SwiftUI
import AVKit

struct SecurityView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("security.cameras") private var savedCameras = Data()
    @State private var showsAddCamera = false
    @State private var selectedCamera: SecurityCamera?

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)
    private let surface = Color(red: 0.97, green: 0.96, blue: 0.97)

    private var cameras: [SecurityCamera] {
        (try? JSONDecoder().decode([SecurityCamera].self, from: savedCameras)) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                         count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    if cameras.isEmpty {
                        cameraCard(name: "Front door", camera: nil)
                        cameraCard(name: "Back garden", camera: nil)
                    } else {
                        ForEach(cameras) { camera in
                            cameraCard(name: camera.name, camera: camera)
                        }
                    }
                }
                presenceCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(surface)
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showsAddCamera) {
            AddSecurityCameraView { camera in
                var updated = cameras
                updated.append(camera)
                if let data = try? JSONEncoder().encode(updated) { savedCameras = data }
            }
        }
        .sheet(item: $selectedCamera) { camera in
            SecurityCameraPlayerView(camera: camera)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR HOME, AT A GLANCE")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                Text("Security")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ink)
            }
            Spacer(minLength: 0)
            Button { showsAddCamera = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ink)
                    .frame(width: 48, height: 48)
                    .background(.white, in: Circle())
                    .overlay(Circle().strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add camera")
        }
    }

    private func cameraCard(name: String, camera: SecurityCamera?) -> some View {
        Button {
            if let camera { selectedCamera = camera } else { showsAddCamera = true }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(camera == nil ? "SET UP" : "CAMERA")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 1, green: 0.91, blue: 0.95), in: Capsule())
                    Spacer(minLength: 0)
                    Image(systemName: camera == nil ? "plus" : "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(.white)
                }
                Image(systemName: "video")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(camera == nil ? "No camera connected" : "Tap to view stream")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .bottomLeading)
            .background(
                LinearGradient(colors: [Color(red: 0.47, green: 0.43, blue: 0.46),
                                        Color(red: 0.23, green: 0.20, blue: 0.23)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(camera == nil ? "Set up \(name) camera" : "View \(name) camera")
    }

    private var presenceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Presence").font(.title3.weight(.bold)).foregroundStyle(ink)
                    Spacer()
                    Text("Not connected").font(.subheadline).foregroundStyle(muted)
                }
                Text("Presence").font(.title3.weight(.bold)).foregroundStyle(ink)
            }
            HStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(Color(red: 1, green: 0.91, blue: 0.95), in: Circle())
                Text("No presence data available yet.")
                    .font(.subheadline)
                    .foregroundStyle(muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
        .shadow(color: ink.opacity(0.05), radius: 14, y: 7)
    }
}

private struct SecurityCamera: Identifiable, Codable {
    var id = UUID()
    let name: String
    let streamURL: URL
}

private struct AddSecurityCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var streamAddress = ""
    let onAdd: (SecurityCamera) -> Void

    private var streamURL: URL? {
        guard let url = URL(string: streamAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Camera name", text: $name)
                    TextField("Stream URL", text: $streamAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                } header: {
                    Text("Camera")
                } footer: {
                    Text("Use an HTTP or HTTPS video stream supported by your device, such as HLS (.m3u8). RTSP and camera sign-in are not supported.")
                }
            }
            .navigationTitle("Add camera")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let streamURL else { return }
                        onAdd(SecurityCamera(name: name.trimmingCharacters(in: .whitespacesAndNewlines), streamURL: streamURL))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || streamURL == nil)
                }
            }
        }
    }
}

private struct SecurityCameraPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let camera: SecurityCamera
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .navigationTitle(camera.name)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear {
                    player = AVPlayer(url: camera.streamURL)
                    player?.play()
                }
                .onDisappear {
                    player?.pause()
                    player = nil
                }
        }
    }
}

#Preview {
    NavigationStack { SecurityView() }
}
