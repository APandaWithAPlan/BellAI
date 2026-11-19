import Foundation
import Observation

struct ServerStatus: Identifiable {
    let name: String
    let port: Int
    let isUp: Bool
    var id: String { name }
}

// starts, stops and watches macserver on this Mac, by running its start.sh like the menu bar app in macserver/menubar does
@MainActor @Observable
final class ServerController {
    // the servers start.sh runs, with the address each answers on when ready
    private static let servers: [(name: String, port: Int, path: String)] = [
        ("Chat model", 11434, "/v1/models"),
        ("Voice", 8000, "/health"),
        ("Data", 8001, "/health"),
        ("Food", 8002, "/health"),
        ("Insights", 8004, "/insights/health"),
        ("Mail", 8003, "/health"),
    ]
    // start.sh writes logs/<name>.log for each; "app" is start.sh's own output when this app started it
    static let logNames = ["app", "llm", "voice", "data", "food", "insights", "mail", "discord"]

    private static let folderKey = "macserverFolder"

    private(set) var folder: URL?
    private(set) var statuses: [ServerStatus] = []
    private(set) var hasChecked = false
    // what the button last asked for (true = start, false = stop), until the servers catch up
    private(set) var pending: Bool?
    private var launcher: Process?

    // mail is optional (setup.sh email turns it on), so it only shows while it answers
    var visible: [ServerStatus] { statuses.filter { $0.name != "Mail" || $0.isUp } }
    var anyUp: Bool { statuses.contains { $0.isUp } }
    var allUp: Bool { hasChecked && visible.allSatisfy(\.isUp) }

    var summary: String {
        if !hasChecked { return "Checking servers…" }
        if pending == true { return "Starting servers…" }
        if pending == false { return "Stopping servers…" }
        if !anyUp { return "Servers stopped" }
        let down = visible.filter { !$0.isUp }.count
        return down == 0 ? "Servers running" : "\(down) of \(visible.count) servers down"
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.folderKey)
        let built = Bundle.main.object(forInfoDictionaryKey: "MacserverFolder") as? String
        folder = [saved, built].compactMap { $0 }.map { URL(fileURLWithPath: $0).standardizedFileURL }
            .first(where: Self.hasStartScript)
    }

    private static func hasStartScript(_ dir: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent("start.sh").path)
    }

    // false if there is no start.sh in it
    func setFolder(_ url: URL) -> Bool {
        guard Self.hasStartScript(url) else { return false }
        folder = url.standardizedFileURL
        UserDefaults.standard.set(folder?.path, forKey: Self.folderKey)
        return true
    }

    func toggle() {
        guard let folder, pending == nil else { return }
        if anyUp || launcher?.isRunning == true {
            pending = false
            launcher = nil
            // start.sh stops every server it started when it gets TERM, whoever ran it
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            kill.arguments = ["-TERM", "-f", #"(^|/)start\.sh"#]
            try? kill.run()
            kill.waitUntilExit()
            if kill.terminationStatus != 0 { pending = nil } // no start.sh running, so something else started them
        } else {
            let logs = folder.appendingPathComponent("logs")
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("app.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let start = Process()
            start.executableURL = URL(fileURLWithPath: "/bin/sh")
            start.arguments = [folder.appendingPathComponent("start.sh").path]
            start.currentDirectoryURL = folder
            // an app starts with almost no PATH, and start.sh needs uv
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
            start.environment = env
            let output = try? FileHandle(forWritingTo: log)
            start.standardOutput = output
            start.standardError = output
            guard (try? start.run()) != nil else { return }
            launcher = start
            pending = true
        }
    }

    // the end of a server's log, or nil if it has none yet
    func tail(of name: String, bytes: Int = 16_000) -> String? {
        guard let folder, let handle = try? FileHandle(forReadingFrom: folder.appendingPathComponent("logs/\(name).log")) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    }

    func poll() async {
        while !Task.isCancelled {
            await check()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func check() async {
        var results: [String: Bool] = [:]
        await withTaskGroup(of: (String, Bool).self) { group in
            for server in Self.servers {
                group.addTask {
                    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)\(server.path)")!)
                    request.timeoutInterval = 2
                    let response = try? await URLSession.shared.data(for: request).1 as? HTTPURLResponse
                    return (server.name, (200..<300).contains(response?.statusCode ?? 0))
                }
            }
            for await (name, isUp) in group { results[name] = isUp }
        }
        statuses = Self.servers.map { ServerStatus(name: $0.name, port: $0.port, isUp: results[$0.name] ?? false) }
        hasChecked = true
        if let want = pending, anyUp == want || (want && launcher?.isRunning != true) { pending = nil }
    }
}
