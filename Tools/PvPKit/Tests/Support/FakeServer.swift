import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum FakeServerError: Error, CustomStringConvertible {
    case nodeNotFound(String)
    case didNotStart(String)

    var description: String {
        switch self {
        case let .nodeNotFound(path): "node not found in PATH (\(path)); the fake PvP server needs Node.js 22.5 or newer"
        case let .didNotStart(output): "the fake PvP server did not start: \(output)"
        }
    }
}

final class FakeServer: Sendable {
    let port: Int
    private let process: Process

    var baseURL: String { "http://127.0.0.1:\(port)" }

    init(config: [String: Any] = [:]) throws {
        let script = Self.packageDirectory.appendingPathComponent("Server/pvp-server.mjs")
        let process = Process()
        process.executableURL = try Self.node()
        let configText = String(decoding: try JSONSerialization.data(withJSONObject: config), as: UTF8.self)
        process.arguments = ["--no-warnings", script.path, "--port", "0", "--config", configText]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        var line = Data()
        while true {
            let byte = output.fileHandleForReading.readData(ofLength: 1)
            if byte.isEmpty || byte == Data("\n".utf8) { break }
            line.append(byte)
        }
        struct Started: Decodable { let port: Int }
        guard let started = try? JSONDecoder().decode(Started.self, from: line) else {
            process.terminate()
            process.waitUntilExit()
            let stderr = errors.fileHandleForReading.readDataToEndOfFile()
            throw FakeServerError.didNotStart(String(decoding: line + stderr, as: UTF8.self))
        }
        self.port = started.port
        self.process = process
    }

    static func node() throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates = path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
        for directory in candidates {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("node")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw FakeServerError.nodeNotFound(path)
    }

    static var packageDirectory: URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
            directory.deleteLastPathComponent()
        }
        return directory
    }

    deinit {
        process.terminate()
    }

    @discardableResult
    func control(_ path: String, _ body: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(baseURL)/__control/\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func request(_ method: String, _ path: String, token: String? = nil, body: [String: Any]? = nil) async throws -> (status: Int, json: [String: Any]) {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    func signIn() async throws -> (token: String, uid: String) {
        let secret = (0..<43).map { _ in String("abcdefghijklmnopqrstuvwxyz".randomElement()!) }.joined()
        let reply = try await request("POST", "/v1/auth/anonymous", body: ["deviceSecret": secret])
        let user = reply.json["user"] as? [String: Any]
        return (reply.json["accessToken"] as? String ?? "", user?["uid"] as? String ?? "")
    }

    func createRoom(_ body: [String: Any]) async throws -> (uid: String, code: String, ticket: String, socketURL: URL) {
        let player = try await signIn()
        let reply = try await request("POST", "/v1/pvp/rooms", token: player.token, body: body)
        return (player.uid, reply.json["code"] as? String ?? "", reply.json["ticket"] as? String ?? "", URL(string: reply.json["socketURL"] as? String ?? "")!)
    }

    func join(_ code: String) async throws -> (uid: String, ticket: String, socketURL: URL) {
        let player = try await signIn()
        let reply = try await request("POST", "/v1/pvp/rooms/\(code)/ticket", token: player.token)
        return (player.uid, reply.json["ticket"] as? String ?? "", URL(string: reply.json["socketURL"] as? String ?? "")!)
    }

    func received(by uid: String) async throws -> [(at: Double, via: String, text: String)] {
        let reply = try await control("received", ["uid": uid])
        let messages = reply["messages"] as? [[String: Any]] ?? []
        return messages.map { (($0["at"] as? Double) ?? 0, ($0["via"] as? String) ?? "", ($0["text"] as? String) ?? "") }
    }
}

func waitUntil(timeout: Duration = .seconds(20), _ condition: () async throws -> Bool) async throws -> Bool {
    let clock = ContinuousClock()
    let end = clock.now + timeout
    while clock.now < end {
        if try await condition() { return true }
        try await Task.sleep(for: .milliseconds(50))
    }
    return false
}
