import FirebaseAuth

/// Firebase owns credential storage and session persistence; passwords are never saved by the app.
final class FirebaseAuthService {
    private let auth = Auth.auth()
    private var listener: AuthStateDidChangeListenerHandle?

    func observeSession(_ onChange: @escaping @Sendable (String?, String?) -> Void) {
        if let listener { auth.removeStateDidChangeListener(listener) }
        listener = auth.addStateDidChangeListener { _, user in
            // Old anonymous sessions must not bypass the email/password login screen.
            let isRegistered = user?.isAnonymous == false
            onChange(isRegistered ? user?.uid : nil, isRegistered ? user?.displayName : nil)
        }
    }

    func signUp(email: String, password: String) async throws {
        _ = try await auth.createUser(withEmail: email, password: password)
    }

    func updateName(firstName: String, lastName: String) async throws {
        guard let user = auth.currentUser, !user.isAnonymous else {
            throw NSError(domain: "BellAI.Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please sign in again."])
        }
        let change = user.createProfileChangeRequest()
        change.displayName = "\(firstName) \(lastName)"
        try await change.commitChanges()
    }

    func login(email: String, password: String) async throws {
        _ = try await auth.signIn(withEmail: email, password: password)
    }

    var email: String { auth.currentUser?.email ?? "" }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let user = auth.currentUser, let email = user.email, !user.isAnonymous else {
            throw NSError(domain: "BellAI.Auth", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Please sign in again."])
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        _ = try await user.reauthenticate(with: credential)
        try await user.updatePassword(to: newPassword)
    }

    func changeEmail(to email: String, currentPassword: String) async throws {
        guard let user = auth.currentUser, let oldEmail = user.email, !user.isAnonymous else {
            throw NSError(domain: "BellAI.Auth", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Please sign in again."])
        }
        let credential = EmailAuthProvider.credential(withEmail: oldEmail, password: currentPassword)
        _ = try await user.reauthenticate(with: credential)
        try await user.sendEmailVerification(beforeUpdatingEmail: email)
    }

    func logout() throws {
        try auth.signOut()
    }

    deinit {
        if let listener { auth.removeStateDidChangeListener(listener) }
    }
}
