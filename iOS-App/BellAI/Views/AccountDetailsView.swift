import SwiftUI

struct AccountDetailsView: View {
    @Bindable var model: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var success: String?
    private let accent = Color(red: 1, green: 0.18, blue: 0.45)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .disabled(model.isLocalTestSession)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Use this email to log in. To change it, enter your current password below and verify the new address using the emailed link.")
                }
                .disabled(isSaving)

                if model.isLocalTestSession {
                    Section {
                        Text("Profile changes last for this test session. Email and password changes aren't available for the local test account.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        SecureField("Current password", text: $currentPassword)
                            .textContentType(.password)
                        SecureField("New password", text: $newPassword)
                            .textContentType(.newPassword)
                        SecureField("Confirm new password", text: $confirmPassword)
                            .textContentType(.newPassword)
                    } header: {
                        Text("Password & security")
                    } footer: {
                        Text("Leave these fields blank to keep your password. A new password must have at least 6 characters.")
                    }
                    .disabled(isSaving)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).accessibilityLabel("Error: \(error)") }
                }
                if let success {
                    Section { Text(success).foregroundStyle(.green) }
                }
                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView() }
                            Text(isSaving ? "Saving…" : "Save")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("Account details")
            .navigationBarTitleDisplayMode(.inline)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                firstName = model.firstName
                lastName = model.lastName
                email = model.email
            }
            .onDisappear { clearPasswords() }
        }
    }

    private func save() {
        guard !isSaving else { return }
        error = nil
        success = nil
        guard newPassword == confirmPassword else {
            error = "Your new passwords don't match."
            return
        }
        let changesEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(model.email) != .orderedSame
        guard currentPassword.isEmpty || !newPassword.isEmpty || changesEmail else {
            error = "Enter a new password, or clear your current password to save only your profile."
            return
        }
        isSaving = true
        Task {
            let result = await model.saveAccountDetails(
                firstName: firstName, lastName: lastName, email: email,
                currentPassword: currentPassword, newPassword: newPassword)
            clearPasswords()
            isSaving = false
            error = result
            if result == nil {
                firstName = model.firstName
                lastName = model.lastName
                success = changesEmail ? "Profile saved. Check your new email for a verification link. Keep using your current email to log in until you verify the new address." : "Account details saved."
            }
        }
    }

    private func clearPasswords() {
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
    }
}
