import Foundation
import Observation

// the servers start.sh runs, with the address each one answers on when it is ready
private let servers: [(name: String, port: Int, path: String)] = [
    ("Chat model", 11434, "/v1/models"),
    ("Voice", 8000, "/health"),
    ("Data", 8001, "/health"),
    ("Food", 8002, "/health"),
    ("Insights", 8004, "/insights/health"),
    ("Mail", 8003, "/health"),
]

// the macserver folder (the one with start.sh) above wherever this was built
private let serverDir: URL? = {
    var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
    while let current = dir, current.path != "/" {
        if FileManager.default.fileExists(atPath: current.appendingPathComponent("start.sh").path) { return current }
        dir = current.deletingLastPathComponent()
    }
    return nil
}()

struct ServerStatus: Identifiable {
    let name: String
    let port: Int
    let isUp: Bool
    var id: String { name }
}

@MainActor
@Observable
final class ServerMonitor {
    private(set) var statuses: [ServerStatus] = []
    private(set) var hasChecked = false
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        return URLSession(configuration: config)
    }()

    // mail is optional (setup.sh email turns it on), so it only shows while it answers
    var visible: [ServerStatus] { statuses.filter { $0.name != "Mail" || $0.isUp } }
    var downCount: Int { visible.filter { !$0.isUp }.count }
    var anyUp: Bool { statuses.contains { $0.isUp } }
    var canControl: Bool { serverDir != nil }

    // what the button last asked for (true = start, false = stop), until the servers catch up
    private(set) var pending: Bool?
    private var launcher: Process?

    func toggle() {
        guard let dir = serverDir else { return }
        if anyUp || launcher?.isRunning == true {
            pending = false
            launcher = nil
            // start.sh stops every server it started when it gets TERM, whoever ran it
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            kill.arguments = ["-TERM", "-f", #"(^|/)start\.sh"#]
            try? kill.run()
            kill.waitUntilExit()
            if kill.terminationStatus != 0 { pending = nil }  // no start.sh running, so something else started them
        } else {
            let logs = dir.appendingPathComponent("logs")
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("menubar.log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let start = Process()
            start.executableURL = URL(fileURLWithPath: "/bin/sh")
            start.arguments = [dir.appendingPathComponent("start.sh").path]
            start.currentDirectoryURL = dir
            // a login item starts with almost no PATH, and start.sh needs uv
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

    func poll() async {
        while !Task.isCancelled {
            await check()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func check() async {
        let session = session
        var results: [String: Bool] = [:]
        await withTaskGroup(of: (String, Bool).self) { group in
            for server in servers {
                group.addTask {
                    let url = URL(string: "http://127.0.0.1:\(server.port)\(server.path)")!
                    let response = try? await session.data(from: url).1 as? HTTPURLResponse
                    return (server.name, (200..<300).contains(response?.statusCode ?? 0))
                }
            }
            for await (name, isUp) in group { results[name] = isUp }
        }
        statuses = servers.map { ServerStatus(name: $0.name, port: $0.port, isUp: results[$0.name] ?? false) }
        hasChecked = true
        if let want = pending, anyUp == want || (want && launcher?.isRunning != true) { pending = nil }
    }
}
