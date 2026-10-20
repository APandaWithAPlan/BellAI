import Foundation

struct TaskItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var title: String
    var isDone = false
}
