#if DEBUG
import Foundation

/// Temporary local task storage for the development login; never calls Firebase.
@MainActor
final class LocalTestUserDataStore: UserDataStore {
    private var data: [String: Any]?

    func load() async throws -> [String: Any]? { data }
    func save(_ data: [String: Any]) async throws { self.data = data }
}
#endif
