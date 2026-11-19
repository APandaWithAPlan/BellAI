import SwiftUI

// Apple Music on the Activity screen: connect, new song ideas, and music that follows the workout
struct MusicCardView: View {
    var model: MusicViewModel

    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Music").font(.title3.weight(.bold)).foregroundStyle(ink)
            if model.isAuthorized {
                connected
            } else {
                Text("Connect Apple Music and BellAI learns what you listen to, suggests new songs, and can match the music to your workout.")
                    .font(.subheadline).foregroundStyle(muted)
                Button("Connect Apple Music") { Task { await model.connect() } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90)))
        .shadow(color: ink.opacity(0.05), radius: 14, y: 7)
        .alert("Apple Music", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var connected: some View {
        Toggle(isOn: Binding(get: { model.followsWorkout }, set: { model.setFollowingWorkout($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Match music to my workout").font(.subheadline.weight(.medium))
                Text(workoutStatus).font(.caption).foregroundStyle(muted)
            }
        }
        .tint(accent)

        if model.suggestions.isEmpty {
            Text("Songs you play are logged so BellAI can learn your taste.").font(.caption).foregroundStyle(muted)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.suggestions) { song in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title).font(.subheadline.weight(.medium))
                        Text(song.artist).font(.caption).foregroundStyle(muted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .foregroundStyle(ink)
        }

        if model.isBusy {
            HStack(spacing: 12) {
                ProgressView()
                Text("Working…").font(.subheadline).foregroundStyle(muted)
            }
        } else {
            HStack(spacing: 20) {
                Button(model.suggestions.isEmpty ? "Suggest songs" : "Suggest again") { Task { await model.suggest() } }
                if !model.suggestions.isEmpty {
                    if let name = model.createdPlaylist {
                        Label("Saved “\(name)”", systemImage: "checkmark.circle").foregroundStyle(muted)
                    } else {
                        Button("Create playlist") { Task { await model.createPlaylist() } }
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accent)
        }
    }

    private var workoutStatus: String {
        guard model.followsWorkout else { return "Heart rate and activity pick the music while the app is open." }
        return model.intensity.map { "Playing \($0.title.lowercased()) music" } ?? "Checking how hard you’re working…"
    }
}
