import SwiftUI

struct TasksView: View {
    @Environment(Features.self) private var features
    @State private var draft = ""

    var body: some View {
        let model = features.tasks
        let open = model.tasks.filter { !$0.isDone }.count
        Page("Tasks", subtitle: model.isLoaded && !model.tasks.isEmpty ? "\(open) open" : nil) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "plus").foregroundStyle(Theme.accent)
                    TextField("Add a task", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .onSubmit(add)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .panel()
                .disabled(!model.isLoaded)

                if let error = model.errorMessage {
                    ProblemLine(text: error) { Task { await model.reload() } }
                }
                if !model.isLoaded && model.errorMessage == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if model.isLoaded && model.tasks.isEmpty {
                    EmptyNote(symbol: "checklist", text: "Nothing to do. Add a task above.")
                } else {
                    Rows(items: model.tasks) { task in
                        TaskRow(task: task)
                    }
                }
            }
        }
        .task { await model.load() }
    }

    private func add() {
        if features.tasks.add(draft) { draft = "" }
    }
}

private struct TaskRow: View {
    @Environment(Features.self) private var features
    @State private var hovering = false
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Button { features.tasks.toggle(task) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(task.isDone ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark \(task.title) not done" : "Mark \(task.title) done")

            Text(task.title)
                .font(.system(size: 15))
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
            Spacer()
            Button {
                if let index = features.tasks.tasks.firstIndex(where: { $0.id == task.id }) {
                    features.tasks.delete(at: IndexSet(integer: index))
                }
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Delete task")
            .accessibilityLabel("Delete \(task.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
