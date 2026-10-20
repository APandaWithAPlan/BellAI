import Foundation
import Observation

// wherever the user's data lives, firebase in the app and a stub in the checks
@MainActor
protocol UserDataStore {
    func load() async throws -> [String: Any]?
    func save(_ data: [String: Any]) async throws
}

@MainActor
@Observable
final class TasksViewModel {
    private(set) var tasks: [TaskItem] = []
    private(set) var isLoaded = false
    var errorMessage: String?

    private let store: any UserDataStore
    // everything saved for the user, kept so saving tasks doesn't wipe the rest
    private var stored: [String: Any] = [:]
    private var lastSave: Task<Void, Never>?

    init(store: any UserDataStore) {
        self.store = store
    }

    // safe to call again, does nothing once loaded
    func load() async {
        guard !isLoaded else { return }
        do {
            stored = try await store.load() ?? [:]
            if let raw = stored["tasks"] {
                let data = try JSONSerialization.data(withJSONObject: raw)
                tasks = try JSONDecoder().decode([TaskItem].self, from: data)
            }
            isLoaded = true
        } catch {
            errorMessage = "Couldn't load your tasks. \(error.localizedDescription)"
        }
    }

    // false if blank, or if we haven't loaded yet (a save would overwrite what's stored)
    @discardableResult
    func add(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLoaded, !trimmed.isEmpty else { return false }
        tasks.append(TaskItem(title: String(trimmed.prefix(200))))
        persist()
        return true
    }

    func toggle(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
        persist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { tasks.remove(at: index) }
        persist()
    }

    // for the assistant, nil until loaded so it never hears "no tasks" before we know
    var openTaskSummary: String? {
        guard isLoaded else { return nil }
        let open = tasks.filter { !$0.isDone }.map(\.title)
        guard !open.isEmpty else { return "I have no open tasks" }
        let shown = open.prefix(20).joined(separator: "; ")
        let extra = open.count > 20 ? " (and \(open.count - 20) more)" : ""
        return "my open tasks are: \(shown)\(extra)"
    }

    // lets the checks wait for saving to finish
    func waitForSaves() async {
        await lastSave?.value
    }

    // saves run one after another so an old save can't land after a newer one
    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks),
              let json = try? JSONSerialization.jsonObject(with: data) else { return }
        stored["tasks"] = json
        let snapshot = stored
        let previous = lastSave
        lastSave = Task {
            await previous?.value
            do {
                try await store.save(snapshot)
            } catch {
                errorMessage = "Couldn't save your tasks. \(error.localizedDescription)"
            }
        }
    }
}
