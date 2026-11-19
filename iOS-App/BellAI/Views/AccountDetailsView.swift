import SwiftUI

struct AccountDetailsView: View {
    var model: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
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
                } header: {
                    Text("Profile")
                } footer: {
                    Text("This is the name BellAI greets you with. It stays on this phone. There is no account to log in to: being connected to your Tailscale network is the login.")
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
                            Text("Save")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                firstName = model.firstName
                lastName = model.lastName
            }
        }
    }

    private func save() {
        error = model.save(firstName: firstName, lastName: lastName)
        success = error == nil ? "Profile saved." : nil
        if error == nil {
            firstName = model.firstName
            lastName = model.lastName
        }
    }
}
