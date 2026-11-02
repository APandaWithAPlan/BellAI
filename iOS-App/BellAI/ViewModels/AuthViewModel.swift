import Foundation
import Observation
import FirebaseAuth

@MainActor
@Observable
final class AuthViewModel {
    private var authenticatedUserID: String?
    private(set) var firstName = ""
    private(set) var lastName = ""
    var email: String { isLocalTestSession ? "admin@bellai.com" : service.email }
    private var isRegistering = false
    #if DEBUG
    private(set) var isLocalTestSession = false
    #else
    var isLocalTestSession: Bool { false }
    #endif
    private(set) var registrationAccountCreated = false
    var userID: String? { isRegistering ? nil : authenticatedUserID }
    private(set) var isRestoringSession = true
    private(set) var isLoading = false
    var errorMessage: String?
    private let service = FirebaseAuthService()

    init() {
        service.observeSession { [weak self] userID, displayName in
            Task { @MainActor [weak self] in
                guard self?.isLocalTestSession != true else { return }
                let changedAccount = self?.authenticatedUserID != userID
                self?.authenticatedUserID = userID
                if self?.isRegistering != true, changedAccount {
                    let parts = (displayName ?? "").split(whereSeparator: { $0.isWhitespace })
                    self?.firstName = parts.first.map(String.init) ?? ""
                    self?.lastName = parts.dropFirst().joined(separator: " ")
                }
                self?.isRestoringSession = false
            }
        }
    }

    func login(email: String, password: String) async {
        await authenticate(email: email, password: password)
    }

    func signUp(firstName: String, lastName: String, email: String, password: String) async {
        guard !isLoading else { return }
        errorMessage = nil
        #if DEBUG
        if email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "admin@bellai.com" {
            errorMessage = "This is the local test account. Use Log In instead."
            return
        }
        #endif
        let firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstName.isEmpty, !lastName.isEmpty else {
            errorMessage = "Enter your first and last name."
            return
        }
        guard firstName.count <= 100, lastName.count <= 100 else {
            errorMessage = "Keep each name under 101 characters."
            return
        }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            errorMessage = "Enter a valid email address."
            return
        }
        guard registrationAccountCreated || password.count >= 6 else {
            errorMessage = "Use a password with at least 6 characters."
            return
        }
        isLoading = true
        isRegistering = true
        defer { isLoading = false }
        do {
            if !registrationAccountCreated {
                try await service.signUp(email: email, password: password)
                registrationAccountCreated = true
            }
            try await service.updateName(firstName: firstName, lastName: lastName)
            self.firstName = firstName
            self.lastName = lastName
            registrationAccountCreated = false
            isRegistering = false
        } catch {
            if registrationAccountCreated {
                errorMessage = "Your account was created, but your name couldn't be saved. Tap Sign Up to retry saving your name."
            } else {
                isRegistering = false
                errorMessage = Self.message(for: error)
            }
        }
    }

    func leaveRegistration() {
        errorMessage = nil
        if registrationAccountCreated {
            do {
                try service.logout()
                authenticatedUserID = nil
                registrationAccountCreated = false
                isRegistering = false
            } catch {
                errorMessage = "Couldn't close registration. Please try again."
            }
        }
    }

    private func authenticate(email: String, password: String) async {
        guard !isLoading else { return }
        errorMessage = nil
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            errorMessage = "Enter a valid email address."
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Enter your password."
            return
        }
        #if DEBUG
        if email.lowercased() == "admin@bellai.com" {
            guard password == "admin1234" else {
                errorMessage = "The email or password is incorrect."
                return
            }
            isLocalTestSession = true
            firstName = "Hy"
            lastName = "Vo"
            authenticatedUserID = "local-debug-admin"
            isRestoringSession = false
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.login(email: email, password: password)
            // Navigation is driven exclusively by Firebase's state listener.
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func saveAccountDetails(firstName: String, lastName: String, email: String,
                            currentPassword: String, newPassword: String) async -> String? {
        guard !isLoading else { return "Please wait for the current request." }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let changesEmail = email.caseInsensitiveCompare(self.email) != .orderedSame
        guard !first.isEmpty, !last.isEmpty else { return "Enter your first and last name." }
        guard first.count <= 100, last.count <= 100 else { return "Keep each name under 101 characters." }
        guard email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            return "Enter a valid email address."
        }
        if changesEmail || !newPassword.isEmpty {
            guard !currentPassword.isEmpty else { return "Enter your current password to change your email or password." }
        }
        if !newPassword.isEmpty && newPassword.count < 6 {
            return "Use a password with at least 6 characters."
        }
        isLoading = true
        defer { isLoading = false }
        if isLocalTestSession {
            guard !changesEmail, newPassword.isEmpty else { return "Email and password changes aren't available for the local test account." }
            self.firstName = first
            self.lastName = last
            return nil
        }
        do {
            try await service.updateName(firstName: first, lastName: last)
        } catch { return Self.message(for: error) }
        self.firstName = first
        self.lastName = last
        var passwordChanged = false
        do {
            if !newPassword.isEmpty {
                try await service.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                passwordChanged = true
            }
            if changesEmail {
                try await service.changeEmail(to: email, currentPassword: passwordChanged ? newPassword : currentPassword)
            }
        } catch {
            let saved = passwordChanged ? "Your name and password were saved, but your email wasn't changed. " : "Your name was saved, but your email/password changes weren't completed. "
            return saved + Self.message(for: error)
        }
        return nil
    }

    func logout() {
        errorMessage = nil
        #if DEBUG
        if isLocalTestSession {
            authenticatedUserID = nil
            firstName = ""
            lastName = ""
            isLocalTestSession = false
            return
        }
        #endif
        do { try service.logout() }
        catch { errorMessage = "Couldn't log out. Please try again." }
    }

    private static func message(for error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .requiresRecentLogin: "Please log in again before changing your account."
        case .invalidEmail: "Enter a valid email address."
        case .emailAlreadyInUse: "An account already uses this email. Try logging in."
        case .weakPassword: "Choose a stronger password that meets the project's password policy."
        case .wrongPassword, .userNotFound, .invalidCredential: "The email or password is incorrect."
        case .networkError: "Couldn't connect. Check your internet connection and try again."
        case .tooManyRequests: "Too many attempts. Please wait and try again."
        case .userDisabled: "This account has been disabled."
        case .operationNotAllowed: "Email/password sign-in is not enabled for this Firebase project."
        default: "Authentication failed. Please try again."
        }
    }
}
