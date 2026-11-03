import Foundation

// where the Mac server is. "ai-server" is its name on Tailscale, but any address that reaches it works,
// like its address on NetBird or on the local network. kept on the phone and changed in Settings
nonisolated enum ServerSettings {
    enum Service: String, CaseIterable {
        case chat, voice, data

        var title: String {
            switch self {
            case .chat: "Chat"
            case .voice: "Voice"
            case .data: "Tasks"
            }
        }

        var defaultPort: Int {
            switch self {
            case .chat: 11434
            case .voice: 8000
            case .data: 8001
            }
        }

        // what to ask to see if the server is there
        var healthPath: String {
            switch self {
            case .chat: "api/version"
            case .voice, .data: "health"
            }
        }

        // a build can set its own default here, as host:port in Info.plist
        fileprivate var plistKey: String? {
            switch self {
            case .chat: nil
            case .voice: "VOICE_SERVER_HOST"
            case .data: "DATA_SERVER_HOST"
            }
        }
    }

    private static let hostKey = "server.host"

    private static func portKey(_ service: Service) -> String {
        "server.port.\(service.rawValue)"
    }

    // what the build asks for until someone changes it
    private static func builtIn(_ service: Service, bundle: Bundle) -> (host: String, port: Int) {
        let configured = service.plistKey
            .flatMap { bundle.object(forInfoDictionaryKey: $0) as? String }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configured, !configured.isEmpty, !configured.hasPrefix("$(") else {
            return ("ai-server", service.defaultPort)
        }
        if let colon = configured.lastIndex(of: ":"), let port = Int(configured[configured.index(after: colon)...]) {
            return (String(configured[..<colon]), port)
        }
        return (configured, service.defaultPort)
    }

    static func resolved(_ service: Service, defaults: UserDefaults = .standard, bundle: Bundle = .main) -> (host: String, port: Int) {
        let fallback = builtIn(service, bundle: bundle)
        let host = defaults.string(forKey: hostKey) ?? fallback.host
        let port = defaults.integer(forKey: portKey(service))
        return (host.isEmpty ? fallback.host : host, port > 0 ? port : fallback.port)
    }

    // host:port to reach a server on
    static func address(_ service: Service, defaults: UserDefaults = .standard, bundle: Bundle = .main) -> String {
        let found = resolved(service, defaults: defaults, bundle: bundle)
        return "\(found.host):\(found.port)"
    }

    // what is wrong with an address and ports, or nil if they are fine
    static func problem(host: String, ports: [Service: Int]) -> String? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return "Enter the server's address." }
        guard host.count <= 253, host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else {
            return "Enter just the address, like ai-server or 192.168.1.20, without http:// or a port."
        }
        for (service, port) in ports where !(1...65535).contains(port) {
            return "\(service.title) needs a port between 1 and 65535."
        }
        return nil
    }

    // saves what was entered, or says what is wrong with it. anything left at what the build asks for isn't kept,
    // so a new build's defaults still apply
    static func save(host: String, ports: [Service: Int], defaults: UserDefaults = .standard, bundle: Bundle = .main) -> String? {
        if let problem = problem(host: host, ports: ports) { return problem }
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if Service.allCases.allSatisfy({ builtIn($0, bundle: bundle).host == host }) {
            defaults.removeObject(forKey: hostKey)
        } else {
            defaults.set(host, forKey: hostKey)
        }
        for service in Service.allCases {
            if let port = ports[service], port != builtIn(service, bundle: bundle).port {
                defaults.set(port, forKey: portKey(service))
            } else {
                defaults.removeObject(forKey: portKey(service))
            }
        }
        return nil
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: hostKey)
        for service in Service.allCases { defaults.removeObject(forKey: portKey(service)) }
    }

    static func isReachable(_ service: Service, session: URLSession = .shared) async -> Bool {
        guard let url = URL(string: "http://\(address(service))/\(service.healthPath)") else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 5
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
