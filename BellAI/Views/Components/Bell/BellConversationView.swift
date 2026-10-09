import SwiftUI

/// Sample conversation content until the chat service supplies messages.
struct BellConversationView: View {
    @State private var prompt = "Make the living room cozy and play the playlist from last Sunday."
    @State private var draft = ""
    @State private var isEditing = false
    @State private var showsRoutine = false

    private let response = "Done. I set the lamps to warm at 35% and started ‘Sunday Slowdown’ on the living room speaker."

    var body: some View {
        VStack(spacing: 16) {
            BellMessageCardView(
                position: .trailing,
                title: "YOU",
                symbol: "person.crop.circle",
                message: prompt,
                subtext: "Transcribed on this iPhone"
            ) {
                Button {
                    draft = prompt
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(minHeight: 44)
                }

                ShareLink(item: prompt) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
            }

            BellMessageCardView(
                position: .leading,
                title: "BELL",
                symbol: "sparkles",
                badge: "2.8 sec",
                message: response,
                subtext: "Used your Sunday 7:14 PM routine · Living room + music",
                onRoutineTap: { showsRoutine.toggle() },
                isRoutineExpanded: showsRoutine
            ) {
                ShareLink(item: response) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
            }

            if showsRoutine {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sunday routine")
                        .font(.subheadline.weight(.semibold))
                    Label("Warm lights · 35% brightness", systemImage: "lightbulb")
                    Label("Sunday Slowdown · Living room speaker", systemImage: "music.note")
                }
                .font(.caption)
                .foregroundStyle(Color(red: 0.48, green: 0.43, blue: 0.46))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                TextEditor(text: $draft)
                    .padding()
                    .navigationTitle("Edit prompt")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isEditing = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                                isEditing = false
                            }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview {
    ScrollView {
        BellConversationView()
            .padding(20)
    }
    .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
