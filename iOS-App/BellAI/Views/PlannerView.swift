import SwiftUI

struct PlannerView: View {
    @Bindable var model: TasksViewModel
    @State private var newTitle = ""

    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let muted = Color(red: 0.48, green: 0.43, blue: 0.46)
    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let done = Color(red: 0.10, green: 0.71, blue: 0.43)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Planner")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(ink)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            addField

            if !model.isLoaded {
                loadingState
            } else if model.tasks.isEmpty {
                Text("Nothing here yet. Add your first task above.")
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                taskList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
        .task { await model.load() }
        .alert("Tasks", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var addField: some View {
        HStack(spacing: 10) {
            // explicit colors, the card is always white even in dark mode
            TextField("", text: $newTitle, prompt: Text("Add a task").foregroundStyle(muted))
                .foregroundStyle(ink)
                .tint(accent)
                .submitLabel(.done)
                .onSubmit(add)
                .disabled(!model.isLoaded)

            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(accent)
            }
            .disabled(!model.isLoaded || newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Add task")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accent, lineWidth: 1)
        }
        .padding(.horizontal, 20)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Button("Try again") { Task { await model.load() } }
                .font(.subheadline)
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var taskList: some View {
        List {
            ForEach(model.tasks) { task in
                Button { model.toggle(task) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(task.isDone ? done : muted)
                            .accessibilityHidden(true)
                        Text(task.title)
                            .strikethrough(task.isDone)
                            .foregroundStyle(task.isDone ? muted : ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(task.isDone ? "Done" : "Not done")
                .listRowBackground(Color.white)
            }
            .onDelete(perform: model.delete)
        }
        .scrollContentBackground(.hidden)
    }

    private func add() {
        if model.add(newTitle) { newTitle = "" }
    }
}

// preview store, keeps tasks in memory only
@MainActor
final class PlannerPreviewStore: UserDataStore {
    func load() async throws -> [String: Any]? { nil }
    func save(_ data: [String: Any]) async throws {}
}

#Preview {
    NavigationStack {
        PlannerView(model: TasksViewModel(store: PlannerPreviewStore()))
    }
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
}
