import FirebaseAuth
import FirebaseFunctions

// talks to the cloud functions in /firebase
@MainActor
struct FirebaseUserDataService: UserDataStore {
    // Bind queued operations to the account that created this screen's store.
    private let userID = Auth.auth().currentUser?.uid
    // looked up on use, so previews don't need firebase configured
    private var functions: Functions { Functions.functions() }

    func save(_ data: [String: Any]) async throws {
        try await call("saveUserData", ["data": data])
    }

    // nil if nothing saved yet
    func load() async throws -> [String: Any]? {
        let result = try await call("getUserData")
        return (result.data as? [String: Any])?["data"] as? [String: Any]
    }

    func delete() async throws {
        try await call("deleteUserData")
    }

    @discardableResult
    private func call(_ name: String, _ data: Any? = nil) async throws -> HTTPSCallableResult {
        guard let user = Auth.auth().currentUser, !user.isAnonymous, user.uid == userID else {
            throw NSError(domain: "BellAI.Authentication", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Please log in again to access your data."])
        }
        return try await functions.httpsCallable(name).call(data)
    }
}
