import FirebaseAuth
import FirebaseFunctions

// talks to the cloud functions in /firebase
@MainActor
struct FirebaseUserDataService: UserDataStore {
    // looked up on use, so previews don't need firebase configured
    private var functions: Functions { Functions.functions() }

    // skips if allready signed in
    func signInAnonymouslyIfNeeded() async throws {
        guard Auth.auth().currentUser == nil else { return }
        try await Auth.auth().signInAnonymously()
    }

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
        try await signInAnonymouslyIfNeeded()
        return try await functions.httpsCallable(name).call(data)
    }
}
