import AVKit
import SwiftUI

private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)
private let accent = Color(red: 1, green: 0.18, blue: 0.45)

// every clip the camera has kept, by day, each one a tap from playing
struct CapturesView: View {
    var model: CapturesViewModel
    @State private var selected: Capture?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Previous captures")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ink)
                    .padding(.top, 16)
                if model.isLoaded {
                    Text(model.total == 1 ? "1 clip from the camera" : "\(model.total) clips from the camera")
                        .font(.subheadline)
                        .foregroundStyle(muted)
                }
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(accent)
                    Button("Try again") { Task { await model.load() } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                } else if !model.isLoaded {
                    ProgressView("Loading captures…").frame(maxWidth: .infinity).padding(.top, 24)
                } else if model.captures.isEmpty {
                    Text("No clips yet. They appear here after the camera records some movement.")
                        .font(.subheadline)
                        .foregroundStyle(muted)
                }
                ForEach(model.days()) { day in
                    Text(Self.title(for: day.date))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(muted)
                        .padding(.top, 8)
                    ForEach(day.captures) { capture in
                        CaptureButton(capture: capture, thumbnailURL: model.thumbnailURL(for: capture), showsDay: false) {
                            selected = capture
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(item: $selected) { capture in
            CapturePlayerView(capture: capture, url: model.videoURL(for: capture))
        }
    }

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

// a clip as a row: its picture, when it was and how long, and a way to play it
struct CaptureButton: View {
    let capture: Capture
    let thumbnailURL: URL
    let showsDay: Bool // the row says which day too, for where the days aren't shown as headings
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AsyncImage(url: thumbnailURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color(red: 0.92, green: 0.88, blue: 0.90)
                            Image(systemName: "video").foregroundStyle(muted)
                        }
                    }
                }
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if capture.isAvailable {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(timeText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text([capture.durationText, capture.motionText].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(muted)
                    if !capture.isAvailable {
                        Text("Not available right now")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(accent)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(WhiteCard())
            .opacity(capture.isAvailable ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!capture.isAvailable)
        .accessibilityLabel("Capture from \(timeText), \(capture.durationText) long")
        .accessibilityHint(capture.isAvailable ? "Play" : "Not available right now")
    }

    private var timeText: String {
        guard let date = capture.startedAt else { return "Unknown time" }
        return showsDay
            ? date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            : date.formatted(date: .omitted, time: .shortened)
    }
}

// plays a clip from the Mac as it downloads, so it starts at once and can be scrubbed
struct CapturePlayerView: View {
    let capture: Capture
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var playback: CapturePlayback?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(capture.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Capture")
                    .font(.headline)
                    .foregroundStyle(ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(accent)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ZStack {
                Color.black
                if let playback {
                    VideoPlayer(player: playback.player)
                    if playback.failed {
                        Text("This recording couldn't be played. Check that the Mac is reachable and the drive with the recordings is connected.")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(24)
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text([capture.durationText, capture.motionText].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(muted)
                Text("Recorded when the camera saw movement.")
                    .font(.footnote)
                    .foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Spacer(minLength: 0)
        }
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .onAppear {
            let playback = CapturePlayback(url: url)
            self.playback = playback
            playback.player.play()
        }
        .onDisappear {
            playback?.player.pause()
            playback = nil
        }
    }
}

// the player and whether the clip failed to load
@MainActor
@Observable
final class CapturePlayback {
    let player: AVPlayer
    private(set) var failed = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor in self?.failed = failed }
        }
    }
}
