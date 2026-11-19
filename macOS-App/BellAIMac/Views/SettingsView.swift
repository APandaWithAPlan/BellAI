import SwiftUI

struct SettingsView: View {
    @Environment(ChatStore.self) private var store
    @Environment(Features.self) private var features
    @AppStorage(Prefs.model) private var model = ""
    @State private var host = ServerSettings.resolved(.chat).host
    @State private var ports = Dictionary(uniqueKeysWithValues: ServerSettings.Service.allCases.map { ($0, ServerSettings.resolved($0).port) })
    @State private var problem: String?
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("Address", text: $host, prompt: Text("localhost"))
                ForEach(ServerSettings.Service.allCases, id: \.self) { service in
                    TextField(service.title, value: portBinding(service), format: .number.grouping(.never))
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Where macserver is: \"localhost\" on this Mac, or its name on Tailscale, like ai-server. Chat is the model, Voice is speech, mail, meals and recommendations, and Tasks is the data server, which also lists the camera's captures.")
            }

            Section {
                TextField("Model", text: $model, prompt: Text("First one the server lists"))
            } footer: {
                Text("Only needed if the server lists models that aren't for chat.")
            }

            Section {
                HStack {
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else if saved {
                        Label("Saved", systemImage: "checkmark").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset") { reset() }
                    Button("Save", action: save).keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func portBinding(_ service: ServerSettings.Service) -> Binding<Int> {
        Binding { ports[service] ?? service.defaultPort } set: { ports[service] = $0; saved = false }
    }

    private func save() {
        problem = ServerSettings.save(host: host, ports: ports)
        saved = problem == nil
        if saved { refresh() }
    }

    private func reset() {
        ServerSettings.reset()
        host = ServerSettings.resolved(.chat).host
        for service in ServerSettings.Service.allCases { ports[service] = ServerSettings.resolved(service).port }
        problem = nil
        saved = true
        refresh()
    }

    private func refresh() {
        store.refreshModels()
        Task { await features.reload() }
    }
}
