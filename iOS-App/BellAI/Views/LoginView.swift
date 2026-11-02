import SwiftUI

struct LoginView: View {
    @Bindable var model: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showsRegistration = false
    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text("Welcome to BellAI")
                    .font(.largeTitle.weight(.bold))
                Text("Log in or create an account to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Email").font(.subheadline.weight(.semibold))
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Email")
                    Text("Password").font(.subheadline.weight(.semibold)).padding(.top, 8)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Password")
                }
                .disabled(model.isLoading)

                if let error = model.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(.red)
                        .accessibilityLabel("Error: \(error)")
                }
                if model.isLoading {
                    ProgressView("Please wait…").frame(maxWidth: .infinity)
                }
                Button { submit() } label: {
                    Text("Log In").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
                Button { model.errorMessage = nil; showsRegistration = true } label: {
                    Text("Register").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(accent)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent))
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading)
            }
            .padding(24)
            .padding(.top, 40)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .tint(accent)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .onDisappear { password = "" }
        .navigationDestination(isPresented: $showsRegistration) {
            SignUpView(model: model)
        }
        }

    }

    private func submit() {
        guard !model.isLoading else { return }
        Task {
            await model.login(email: email, password: password)
            password = ""
        }
    }
}
