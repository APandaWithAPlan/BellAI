import SwiftUI

struct RoutineView: View {
    @State private var routines: [Routine] = []
    @State private var isCreating = false
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var deletingIDs: Set<UUID> = []
    @State private var deleteError: String?
    private let notifications = RoutineNotifications.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Routine")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
                Spacer()
                Button { isCreating = true } label: {
                    Label("Create", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 1, green: 0.18, blue: 0.45))
                        .frame(minHeight: 44)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            List {
                Group {
                    if let message = notifications.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        if notifications.permissionDenied {
                            #if os(iOS)
                            Button("Open notification settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                            }
                            #endif
                        }
                    }
                    if isLoading { ProgressView("Loading routines…") }
                    if let loadError {
                        Text(loadError).font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await refresh() } }
                    } else if routines.isEmpty && !isLoading {
                        Text("No routines yet. Tap Create to add one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                ForEach(routines) { routine in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(routine.name).font(.headline)
                        Label("\(routine.time) · \(routine.timezone)", systemImage: "clock")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(Array(routine.actions.enumerated()), id: \.offset) { index, action in
                            Text("\(index + 1). \(action)").font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    .opacity(deletingIDs.contains(routine.id) ? 0.5 : 1)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await delete(routine) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(deletingIDs.contains(routine.id))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .alert("Couldn't delete routine", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "Please try again.")
        }
        .sheet(isPresented: $isCreating) {
            CreateRoutineView { saved in
                routines.removeAll { $0.id == saved.id }
                routines.append(saved)
                routines.sort { ($0.time, $0.name) < ($1.time, $1.name) }
                Task { await refresh() }
            }
        }
    }

    private func delete(_ routine: Routine) async {
        guard deletingIDs.insert(routine.id).inserted else { return }
        defer { deletingIDs.remove(routine.id) }
        do {
            try await notifications.delete(routine)
            withAnimation { routines.removeAll { $0.id == routine.id } }
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            routines = try await notifications.refresh(requestPermission: true)
            loadError = nil
        } catch {
            loadError = "Couldn't load routines. \(error.localizedDescription)"
        }
    }
}

private struct CreateRoutineView: View {
    var onSaved: (Routine) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var id = UUID()
    @State private var name = ""
    @State private var time = Date()
    @State private var actions = [ActionDraft()]
    @State private var isSaving = false
    @State private var saveError: String?

    private struct ActionDraft: Identifiable {
        let id = UUID()
        var text = ""
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanActions: [String] { actions.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) } }
    private var isValid: Bool {
        !cleanName.isEmpty && cleanName.count <= 100 &&
        cleanActions.allSatisfy { !$0.isEmpty && $0.count <= 500 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Routine name", text: $name)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Text(TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    ForEach($actions) { $action in
                        HStack {
                            TextField("Action", text: $action.text, axis: .vertical)
                            if actions.count > 1 {
                                Button(role: .destructive) { actions.removeAll { $0.id == action.id } } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove action")
                            }
                        }
                    }
                    Button("Add action", systemImage: "plus") { actions.append(ActionDraft()) }
                        .disabled(actions.count >= 50)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Describe each action in order, up to 500 characters each. A daily notification reminds you at this time; actions are not run automatically.")
                }
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
            }
            .disabled(isSaving)
            .navigationTitle("Create Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let routine = Routine(id: id, name: cleanName,
                              time: String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0),
                              timezone: TimeZone.current.identifier, actions: cleanActions)
        do {
            let saved = try await HTTPRoutineService().create(routine)
            await RoutineNotifications.shared.saved(saved)
            onSaved(saved)
            dismiss()
        } catch {
            saveError = "Couldn't save routine. \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        RoutineView()
    }
}
