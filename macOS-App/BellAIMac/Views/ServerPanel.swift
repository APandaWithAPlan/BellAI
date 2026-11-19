import AppKit
import SwiftUI

// the small status row at the bottom of the sidebar; opens the panel
struct ServerStatusRow: View {
    @Environment(ServerController.self) private var servers
    @Binding var showPanel: Bool

    var body: some View {
        Button { showPanel = true } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(servers.indicator)
                    .frame(width: 8, height: 8)
                Text(servers.summary).font(.system(size: 13))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Control the BellAI servers")
        .accessibilityLabel("Servers: \(servers.summary). Open server controls")
    }
}

private extension ServerController {
    // green when everything answers, orange when only some do, gray when stopped
    var indicator: Color { !hasChecked ? .secondary : allUp ? .green : anyUp ? .orange : .secondary }
}

struct ServerPanel: View {
    @Environment(ServerController.self) private var servers
    @Environment(\.dismiss) private var dismiss
    @State private var logName = "app"
    @State private var log = ""
    @State private var folderProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if servers.folder == nil {
                missingFolder
            } else {
                statusList
                logView
            }
            footer
        }
        .padding(20)
        .frame(width: 540, height: 560)
        .background(Theme.background)
    }

    private var header: some View {
        HStack {
            Text("Servers").font(.system(size: 20, weight: .semibold))
            Spacer()
            Circle().fill(servers.indicator).frame(width: 8, height: 8)
            Text(servers.summary).foregroundStyle(.secondary)
            Button(servers.anyUp ? "Stop" : "Start") { servers.toggle() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(servers.folder == nil || servers.pending != nil)
        }
    }

    private var statusList: some View {
        VStack(spacing: 0) {
            ForEach(servers.visible) { server in
                HStack(spacing: 10) {
                    Circle().fill(server.isUp ? Color.green : (servers.anyUp ? Color.orange : Color.secondary)).frame(width: 8, height: 8)
                    Text(server.name)
                    Spacer()
                    Text(verbatim: server.isUp ? "Port \(server.port)" : "Not responding")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(server.name) \(server.isUp ? "running" : "not responding")")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Log", selection: $logName) {
                ForEach(ServerController.logNames, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.isEmpty ? "No log yet." : log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(log.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(Theme.code, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                .onChange(of: log) { proxy.scrollTo("end") }
            }
        }
        .task(id: logName) {
            while !Task.isCancelled {
                log = servers.tail(of: logName) ?? ""
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var missingFolder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The macserver folder wasn't found.", systemImage: "exclamationmark.triangle.fill")
            Text("Choose the folder with start.sh in it, from the BellAI repository.")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            if let problem = folderProblem {
                Text(problem).foregroundStyle(.red).font(.caption)
            } else if let folder = servers.folder {
                Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Button("Choose Folder…", action: chooseFolder)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose the macserver folder, the one with start.sh in it"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderProblem = servers.setFolder(url) ? nil : "There is no start.sh in that folder."
    }
}
