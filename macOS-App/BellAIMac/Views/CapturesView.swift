import AVKit
import SwiftUI

// the home camera's earlier clips, by day
struct CapturesView: View {
    @Environment(Features.self) private var features
    @State private var playing: Capture?

    var body: some View {
        let model = features.captures
        Page("Captures", subtitle: model.isLoaded ? "\(model.total) clip\(model.total == 1 ? "" : "s")" : nil) {
            Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
                .disabled(model.isLoading)
        } content: {
            VStack(alignment: .leading, spacing: 24) {
                if let error = model.errorMessage {
                    ProblemLine(text: error) { Task { await model.load() } }
                }
                if !model.isLoaded && model.errorMessage == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if model.isLoaded && model.captures.isEmpty {
                    EmptyNote(symbol: "video", text: "No captures yet. The camera saves a clip when something moves.")
                }
                ForEach(model.days()) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], alignment: .leading, spacing: 14) {
                            ForEach(day.captures) { capture in
                                Tile(capture: capture) { playing = capture }
                            }
                        }
                    }
                }
            }
        }
        .task { await model.load() }
        .sheet(item: $playing) { capture in ClipPlayer(capture: capture) }
    }
}

private struct Tile: View {
    @Environment(Features.self) private var features
    let capture: Capture
    let play: () -> Void

    private var caption: String {
        [capture.startedAt?.formatted(date: .omitted, time: .shortened), capture.durationText, capture.motionText]
            .compactMap { $0 }.joined(separator: "  ·  ")
    }

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: features.captures.thumbnailURL(for: capture)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Theme.userBubble)
                        .overlay { Image(systemName: "video").foregroundStyle(.tertiary) }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                Text(caption).font(.system(size: 12)).foregroundStyle(.secondary)
                if !capture.isAvailable {
                    Text("Drive not connected").font(.system(size: 12)).foregroundStyle(.orange)
                }
            }
            .opacity(capture.isAvailable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!capture.isAvailable)
        .accessibilityLabel("Clip, \(caption)")
    }
}

private struct ClipPlayer: View {
    @Environment(Features.self) private var features
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(capture: Capture) {
        // the URL needs the data server's address, which Features knows, so it is set up in onAppear
        _player = State(initialValue: AVPlayer())
        self.capture = capture
    }

    let capture: Capture

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(capture.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Clip")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(width: 720)
        .background(Theme.background)
        .onAppear {
            player.replaceCurrentItem(with: AVPlayerItem(url: features.captures.videoURL(for: capture)))
            player.play()
        }
        .onDisappear { player.pause() }
    }
}
