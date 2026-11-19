import Foundation

struct Routine: Codable, Identifiable {
    let id: UUID
    let name: String
    let time: String
    let timezone: String
    let actions: [String]
}
