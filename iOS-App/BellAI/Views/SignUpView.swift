import SwiftUI

struct SignUpView: View {
    @Bindable var model: AuthViewModel
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Create your account")
                    .font(.largeTitle.weight(.bold))
                Text("Join BellAI to get started.")
                    .font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("First name").font(.subheadline.weight(.semibold))
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .registrationField()
                    Text("Last name").font(.subheadline.weight(.semibold)).padding(.top, 8)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .autocorrectionDisabled()
                        .registrationField()
                    Text("Email").font(.subheadline.weight(.semibold)).padding(.top, 8)
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .registrationField()
                        .disabled(model.registrationAccountCreated)
                    Text("Password").font(.subheadline.weight(.semibold)).padding(.top, 8)
                    SecureField("At least 6 characters", text: $password)
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .onSubmit(signUp)
                        .registrationField()
                        .disabled(model.registrationAccountCreated)
                }
                .disabled(model.isLoading)
                if let error = model.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(.red)
                        .accessibilityLabel("Error: \(error)")
                }
                if model.isLoading {
                    ProgressView("Creating your account…").frame(maxWidth: .infinity)
                }
                Button(action: signUp) {
                    Text("Sign Up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .tint(accent)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Register")
        .navigationBarBackButtonHidden(model.isLoading)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear {
            password = ""
            model.leaveRegistration()
        }
    }

    private func signUp() {
        guard !model.isLoading else { return }
        Task {
            await model.signUp(firstName: firstName, lastName: lastName, email: email, password: password)
            password = ""
        }
    }
}

private extension View {
    func registrationField() -> some View {
        padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}
