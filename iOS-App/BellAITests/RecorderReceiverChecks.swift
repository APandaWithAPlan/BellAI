import Foundation
import Network

@main
struct RecorderReceiverChecks {
    @MainActor
    static func main() async throws {
        precondition(CRC32.update(0, Data("123456789".utf8)) == 0xCBF43926)
        precondition(CRC32.update(CRC32.update(0, Data("1234".utf8)), Data("56789".utf8)) == 0xCBF43926)

        try checkSetupMessage()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("recorder-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "recorder-checks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let receiver = RecorderReceiver(port: 0, directory: directory, defaults: defaults)
        precondition(receiver.status == .off && receiver.token == RecorderReceiver.defaultToken)
        receiver.isEnabled = true
        for _ in 0..<100 where receiver.status != .listening { try await Task.sleep(for: .milliseconds(50)) }
        precondition(receiver.status == .listening, "listener didn't start: \(receiver.status)")
        let port = receiver.boundPort!
        let base = "http://127.0.0.1:\(port)"

        // the recorder finds the phone by this answer
        let (pingBody, ping) = try await URLSession.shared.data(from: URL(string: "\(base)/ping")!)
        precondition((ping as! HTTPURLResponse).statusCode == 200 && String(decoding: pingBody, as: UTF8.self) == "recorder-receiver")

        // a good upload comes back as OK <bytes> <crc>, and is on disk under its name
        let audio = Data((0..<1_000_000).map { _ in UInt8.random(in: 0...255) })
        let expected = "OK \(audio.count) \(String(CRC32.update(0, audio), radix: 16))"
        let (code, body) = try await upload(base, name: "rec_000001.wav", token: "change-me", body: audio)
        precondition(code == 200 && body == expected, "got \(code) \(body)")
        let first = try Data(contentsOf: directory.appendingPathComponent("rec_000001.wav"))
        precondition(first == audio)
        precondition(receiver.recordingCount == 1 && receiver.lastFile == "rec_000001.wav")

        // a name already taken is kept, not overwritten
        let again = Data("second".utf8)
        let (againCode, _) = try await upload(base, name: "rec_000001.wav", token: "change-me", body: again)
        precondition(againCode == 200)
        let kept = try Data(contentsOf: directory.appendingPathComponent("rec_000001.wav"))
        let copy = try Data(contentsOf: directory.appendingPathComponent("rec_000001-2.wav"))
        precondition(kept == audio && copy == again)

        // wrong token, bad names and unknown paths are turned away and leave nothing behind
        let denied = try await upload(base, name: "rec_000002.wav", token: "nope", body: again).0
        precondition(denied == 403)
        for bad in ["../evil.wav", "rec_000002.txt", "a b.wav", ""] {
            let rejected = try await upload(base, name: bad, token: "change-me", body: again).0
            precondition(rejected == 400, "accepted \(bad)")
        }
        let other = try await URLSession.shared.data(from: URL(string: "\(base)/other")!).1
        precondition(other.isHTTP(404))

        // the token can be changed while listening
        receiver.token = "secret"
        let oldToken = try await upload(base, name: "rec_000003.wav", token: "change-me", body: again).0
        let newToken = try await upload(base, name: "rec_000003.wav", token: "secret", body: again).0
        precondition(oldToken == 403 && newToken == 200)

        // an upload cut short keeps no partial file
        let socket = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        socket.start(queue: .global())
        let head = "POST /upload HTTP/1.1\r\nX-Auth: secret\r\nX-Filename: rec_000004.wav\r\nContent-Length: 100\r\n\r\n"
        socket.send(content: Data(head.utf8) + Data(repeating: 1, count: 10), completion: .idempotent)
        try await Task.sleep(for: .milliseconds(300))
        socket.cancel()
        try await Task.sleep(for: .milliseconds(300))
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        precondition(left == ["rec_000001-2.wav", "rec_000001.wav", "rec_000003.wav"], "found \(left)")

        receiver.isEnabled = false
        precondition(receiver.status == .off)
        print("All recorder receiver checks passed.")
    }

    // the layout the recorder's provision.c parses
    private static func checkSetupMessage() throws {
        let message = try RecorderSetupMessage.encode(token: "tok", ssid: "Home", password: "hunter22")
        precondition(Array(message) == [3] + Array("tok".utf8) + [4] + Array("Home".utf8) + [8] + Array("hunter22".utf8))
        let open = try RecorderSetupMessage.encode(token: "tok", ssid: "Cafe", password: "")
        precondition(Array(open.suffix(1)) == [0])
        func rejected(_ ssid: String, _ password: String) -> RecorderSetupError? {
            do { _ = try RecorderSetupMessage.encode(token: "tok", ssid: ssid, password: password); return nil }
            catch { return error as? RecorderSetupError }
        }
        precondition(rejected("", "hunter22") == .noName)
        precondition(rejected(String(repeating: "a", count: 33), "hunter22") == .nameTooLong)
        precondition(rejected("Home", "short") == .passwordLength)
        precondition(rejected("Home", String(repeating: "a", count: 64)) == .passwordLength)
        precondition(rejected("Ho\nme", "hunter22") == .lineBreak)
        precondition(rejected("Home", "hunter\r22") == .lineBreak)
        // a 32-byte name and 63-byte password is the largest message, and has to fit the firmware's buffer
        let largest = try RecorderSetupMessage.encode(token: "change-me", ssid: String(repeating: "n", count: 32), password: String(repeating: "p", count: 63))
        precondition(largest.count == 3 + 9 + 32 + 63)
    }

    private static func upload(_ base: String, name: String, token: String, body: Data) async throws -> (Int, String) {
        var request = URLRequest(url: URL(string: "\(base)/upload")!)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-Auth")
        request.setValue(name, forHTTPHeaderField: "X-Filename")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
    }
}

private extension URLResponse {
    func isHTTP(_ code: Int) -> Bool { (self as? HTTPURLResponse)?.statusCode == code }
}
