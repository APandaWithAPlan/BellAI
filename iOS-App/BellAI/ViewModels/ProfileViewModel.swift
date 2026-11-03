import Foundation
import Observation

// who the app says hello to, kept on this phone. being on the tailnet is the login, so there are no accounts
@MainActor
@Observable
final class ProfileViewModel {
    private static let firstNameKey = "profile.firstName"
    private static let lastNameKey = "profile.lastName"

    private(set) var firstName: String
    private(set) var lastName: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        firstName = defaults.string(forKey: Self.firstNameKey) ?? ""
        lastName = defaults.string(forKey: Self.lastNameKey) ?? ""
    }

    // returns what went wrong, or nil once it is saved
    func save(firstName: String, lastName: String) -> String? {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !last.isEmpty else { return "Enter your first and last name." }
        guard first.count <= 100, last.count <= 100 else { return "Keep each name under 101 characters." }
        defaults.set(first, forKey: Self.firstNameKey)
        defaults.set(last, forKey: Self.lastNameKey)
        self.firstName = first
        self.lastName = last
        return nil
    }
}
