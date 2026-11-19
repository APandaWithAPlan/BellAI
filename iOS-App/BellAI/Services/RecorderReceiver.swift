import Foundation
import Network
import Observation
import os

// receives the recordings the Pico W clip-on recorder uploads over Wi-Fi (firmware: bellaimic, receiver.py is the reference).
//   GET  /ping      -> 200 "recorder-receiver". the recorder scans its Wi-Fi subnet for this answer to find the phone
//   POST /upload    -> headers X-Auth, X-Filename, Content-Length, then the WAV. replies 200 "OK <bytes> <crc32 hex>"
//                      and the recorder deletes its copy only if both match what it sent
// iOS won't run a server in the background, so this only listens while the app is open. the recorder keeps its files
// and retries every 10 minutes until it finds the phone

nonisolated enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    }

    // same as zlib's crc32(crc, data); start from 0
    static func update(_ crc: UInt32, _ data: Data) -> UInt32 {
        data.withUnsafeBytes { bytes in
            var c = ~crc
            for byte in bytes { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
            return ~c
        }
    }
}

nonisolated struct RecorderRequest: Equatable {
    let method: String
    let path: String
    let headers: [String: String]   // names lowercased

    init?(head: String) {
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        path = String(parts[1])
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        self.headers = headers
    }
}

// one TCP connection from the recorder. everything runs on its own serial queue
nonisolated final class RecorderConnection: @unchecked Sendable {
    static let maxHeadBytes = 8192
    static let maxUploadBytes = 256 << 20     // an hour of audio is 115 MB
    static let idleSeconds = 30.0
    static let pingAnswer = "recorder-receiver"

    private let connection: NWConnection
    private let directory: URL
    private let token: @Sendable () -> String
    private let onSaved: @Sendable (String) -> Void
    private let queue = DispatchQueue(label: "bellai.recorder.connection")

    private var head = Data()
    private var file: FileHandle?
    private var partURL: URL?
    private var name = ""
    private var remaining = 0
    private var total = 0
    private var crc: UInt32 = 0
    private var finished = false
    private var generation = 0

    init(_ connection: NWConnection, directory: URL, token: @escaping @Sendable () -> String, onSaved: @escaping @Sendable (String) -> Void) {
        self.connection = connection
        self.directory = directory
        self.token = token
        self.onSaved = onSaved
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            if case .failed = state { abort() }
        }
        connection.start(queue: queue)
        armTimeout()
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            guard !finished else { return }
            if let data, !data.isEmpty { handle(data) }
            if finished { return }
            if error != nil || isComplete { return abort() }
            armTimeout()
            receive()
        }
    }

    // a recorder that goes quiet mid-upload (power loss, Wi-Fi drop) must not hold a connection and a half file forever
    private func armTimeout() {
        generation += 1
        let mine = generation
        queue.asyncAfter(deadline: .now() + Self.idleSeconds) { [self] in
            if mine == generation, !finished { abort() }
        }
    }

    private func handle(_ data: Data) {
        guard file == nil else { return write(data) }
        head.append(data)
        guard let end = head.range(of: Data("\r\n\r\n".utf8)) else {
            if head.count > Self.maxHeadBytes { reply(431, "header too large") }
            return
        }
        let rest = head[end.upperBound...]
        guard let request = RecorderRequest(head: String(decoding: head[..<end.lowerBound], as: UTF8.self)) else {
            return reply(400, "bad request")
        }
        switch (request.method, request.path) {
        case ("GET", "/ping"):
            reply(200, Self.pingAnswer)
        case ("POST", "/upload"):
            beginUpload(request, firstBytes: Data(rest))
        default:
            reply(404, "not found")
        }
    }

    private func beginUpload(_ request: RecorderRequest, firstBytes: Data) {
        guard request.headers["x-auth"] == token() else { return reply(403, "denied") }
        let name = (request.headers["x-filename"] ?? "") as NSString
        guard name.lastPathComponent == name as String,
              name.range(of: "^[A-Za-z0-9_.-]+\\.wav$", options: .regularExpression).location != NSNotFound else {
            return reply(400, "bad name")
        }
        guard let length = request.headers["content-length"].flatMap({ Int($0) }), length > 0 else {
            return reply(400, "bad length")
        }
        guard length <= Self.maxUploadBytes else { return reply(413, "too large") }
        let part = directory.appendingPathComponent(name as String + ".part")
        guard FileManager.default.createFile(atPath: part.path, contents: nil), let handle = try? FileHandle(forWritingTo: part) else {
            return reply(500, "can't write")
        }
        self.name = name as String
        partURL = part
        file = handle
        remaining = length
        write(firstBytes)
    }

    private func write(_ data: Data) {
        guard let file, !data.isEmpty else { return }
        let chunk = data.prefix(remaining)   // anything past Content-Length isn't ours
        do {
            try file.write(contentsOf: chunk)
        } catch {
            return reply(507, "write failed")
        }
        crc = CRC32.update(crc, chunk)
        total += chunk.count
        remaining -= chunk.count
        if remaining == 0 { save() }
    }

    // the audio is in its final place before the OK goes out, because the OK lets the recorder delete its copy.
    // a name already taken (the recorder restarted its numbering) gets a suffix instead of overwriting a recording
    private func save() {
        guard let partURL else { return }
        try? file?.close()
        file = nil
        let base = (name as NSString).deletingPathExtension
        var destination = directory.appendingPathComponent(name)
        var copy = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            copy += 1
            destination = directory.appendingPathComponent("\(base)-\(copy).wav")
        }
        do {
            try FileManager.default.moveItem(at: partURL, to: destination)
        } catch {
            return reply(500, "can't save")
        }
        self.partURL = nil
        onSaved(destination.lastPathComponent)
        reply(200, "OK \(total) \(String(crc, radix: 16))")
    }

    private func reply(_ code: Int, _ text: String) {
        guard !finished else { return }
        discardPartialFile()
        finished = true
        let reason = code == 200 ? "OK" : "Error"
        let body = Data(text.utf8)
        let header = "HTTP/1.1 \(code) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [self] _ in connection.cancel() })
    }

    private func abort() {
        guard !finished else { return }
        finished = true
        discardPartialFile()
        connection.cancel()
    }

    private func discardPartialFile() {
        try? file?.close()
        file = nil
        if let partURL { try? FileManager.default.removeItem(at: partURL) }
        partURL = nil
    }
}

// the listener, and what Settings shows about it
@MainActor
@Observable
final class RecorderReceiver {
    enum Status: Equatable {
        case off
        case listening
        case failed(String)
    }

    // the recorder's SERVER_PORT in config.h
    nonisolated static let defaultPort: UInt16 = 8080
    // same as the recorder's AUTH_TOKEN until it is changed here and in config.h
    nonisolated static let defaultToken = "change-me"

    private enum Keys {
        static let enabled = "recorder.receive"
        static let token = "recorder.token"
    }

    private(set) var status = Status.off
    private(set) var boundPort: UInt16?
    private(set) var recordingCount = 0
    private(set) var lastFile: String?

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled); sync() }
    }

    var token: String {
        didSet {
            let value = token
            tokenBox.withLock { $0 = value }
            defaults.set(value, forKey: Keys.token)
        }
    }

    let directory: URL
    private let port: UInt16
    private let defaults: UserDefaults
    private let tokenBox: OSAllocatedUnfairLock<String>
    private var listener: NWListener?
    private var isActive = true
    private let queue = DispatchQueue(label: "bellai.recorder.listener")

    init(port: UInt16 = RecorderReceiver.defaultPort, directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.port = port
        self.defaults = defaults
        self.directory = directory ?? URL.documentsDirectory.appendingPathComponent("Recordings", isDirectory: true)
        let saved = defaults.string(forKey: Keys.token).flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultToken
        token = saved
        tokenBox = OSAllocatedUnfairLock(initialState: saved)
        isEnabled = defaults.bool(forKey: Keys.enabled)
        recordingCount = countRecordings()
    }

    // listening only makes sense while the app is open: iOS suspends the listener in the background anyway
    func setActive(_ active: Bool) {
        isActive = active
        sync()
    }

    func resetToken() {
        token = Self.defaultToken
    }

    private func sync() {
        if isEnabled && isActive { start() } else { stop() }
    }

    private func start() {
        guard listener == nil else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port) ?? .any)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    if let listener { self?.listenerChanged(state, listener) }
                }
            }
            let directory = directory
            let tokenBox = tokenBox
            let onSaved: @Sendable (String) -> Void = { [weak self] name in
                Task { @MainActor in self?.saved(name) }
            }
            listener.newConnectionHandler = { connection in
                RecorderConnection(connection, directory: directory, token: { tokenBox.withLock { $0 } }, onSaved: onSaved).start()
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        boundPort = nil
        status = .off
    }

    private func listenerChanged(_ state: NWListener.State, _ changed: NWListener) {
        guard changed === listener else { return }   // a listener already stopped
        switch state {
        case .ready:
            boundPort = changed.port?.rawValue
            status = .listening
        case .failed(let error):
            stop()
            status = .failed(error.localizedDescription)
        default:
            break
        }
    }

    private func saved(_ name: String) {
        lastFile = name
        recordingCount = countRecordings()
    }

    private func countRecordings() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".wav") }.count
    }
}
