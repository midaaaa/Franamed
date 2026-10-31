import Foundation
import Synchronization
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

struct POSIXWebSockets: PvPWebSocketFactory {
    static let open = Mutex<Set<Int32>>([])

    static func dropAll() {
        for fd in open.withLock({ $0 }) { shutdown(fd, Int32(SHUT_RDWR)) }
    }

    func open(_ request: URLRequest) -> any PvPWebSocket {
        let socket = POSIXWebSocket()
        let thread = Thread { socket.run(request) }
        thread.start()
        return socket
    }
}

final class POSIXWebSocket: PvPWebSocket {
    private struct Inbox {
        var frames: [PvPSocketFrame] = []
        var waiter: CheckedContinuation<PvPSocketFrame, Never>?
        var ended = false
    }

    private let inbox = Mutex(Inbox())
    private let descriptor = Mutex<Int32>(-1)
    private let writing = NSLock()

    func receive() async -> PvPSocketFrame {
        await withCheckedContinuation { continuation in
            let ready: PvPSocketFrame? = inbox.withLock { inbox in
                if !inbox.frames.isEmpty { return inbox.frames.removeFirst() }
                inbox.waiter = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    func send(_ text: String) async throws {
        try write(opcode: 1, payload: Array(text.utf8))
    }

    func close(code: Int) {
        let payload = [UInt8(code >> 8), UInt8(code & 255)]
        try? write(opcode: 8, payload: payload)
        let fd = descriptor.withLock { $0 }
        if fd >= 0 { shutdown(fd, Int32(SHUT_RDWR)) }
        push(.closed(code: nil, reason: nil, status: nil))
    }

    // MARK: Connection

    fileprivate func run(_ request: URLRequest) {
        guard let url = request.url, let host = url.host, let fd = connect(host: host, port: url.port ?? 80) else {
            push(.closed(code: nil, reason: nil, status: nil))
            return
        }
        descriptor.withLock { $0 = fd }
        POSIXWebSockets.open.withLock { _ = $0.insert(fd) }
        defer {
            POSIXWebSockets.open.withLock { _ = $0.remove(fd) }
            Glibc_close(fd)
        }

        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        var head = "GET \(url.path)\(url.query.map { "?\($0)" } ?? "") HTTP/1.1\r\nHost: \(host):\(url.port ?? 80)\r\n"
        head += "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: \(key)\r\n"
        for (name, value) in request.allHTTPHeaderFields ?? [:] { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        guard (try? raw(Array(head.utf8))) != nil else {
            push(.closed(code: nil, reason: nil, status: nil))
            return
        }

        var buffer: [UInt8] = []
        while !buffer.containsHeaderEnd {
            guard let chunk = read(fd) else {
                push(.closed(code: nil, reason: nil, status: nil))
                return
            }
            buffer += chunk
        }
        let end = buffer.headerEnd
        let status = Int(String(decoding: buffer[..<end], as: UTF8.self).split(separator: " ").dropFirst().first ?? "") ?? 0
        guard status == 101 else {
            push(.closed(code: nil, reason: nil, status: status))
            return
        }
        buffer.removeFirst(end + 4)

        var message: [UInt8] = []
        while true {
            while let (fin, opcode, payload, used) = Self.frame(in: buffer) {
                buffer.removeFirst(used)
                switch opcode {
                case 0, 1, 2:
                    message += payload
                    if fin {
                        push(.text(String(decoding: message, as: UTF8.self)))
                        message = []
                    }
                case 8:
                    let code = payload.count >= 2 ? Int(payload[0]) << 8 | Int(payload[1]) : nil
                    let reason = payload.count > 2 ? String(decoding: payload[2...], as: UTF8.self) : nil
                    push(.closed(code: code, reason: reason, status: nil))
                    return
                case 9:
                    try? write(opcode: 10, payload: payload)
                default:
                    break
                }
            }
            guard let chunk = read(fd) else {
                push(.closed(code: nil, reason: nil, status: nil))
                return
            }
            buffer += chunk
        }
    }

    private func push(_ frame: PvPSocketFrame) {
        let waiter: CheckedContinuation<PvPSocketFrame, Never>? = inbox.withLock { inbox in
            guard !inbox.ended else { return nil }
            if case .closed = frame { inbox.ended = true }
            if let waiter = inbox.waiter {
                inbox.waiter = nil
                return waiter
            }
            inbox.frames.append(frame)
            return nil
        }
        waiter?.resume(returning: frame)
    }

    private func write(opcode: UInt8, payload: [UInt8]) throws {
        var frame: [UInt8] = [0x80 | opcode]
        if payload.count < 126 {
            frame.append(0x80 | UInt8(payload.count))
        } else if payload.count < 65536 {
            frame += [0x80 | 126, UInt8(payload.count >> 8), UInt8(payload.count & 255)]
        } else {
            frame.append(0x80 | 127)
            frame += (0..<8).reversed().map { UInt8((payload.count >> ($0 * 8)) & 255) }
        }
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame += mask
        frame += payload.enumerated().map { $1 ^ mask[$0 % 4] }
        try raw(frame)
    }

    private func raw(_ bytes: [UInt8]) throws {
        writing.lock()
        defer { writing.unlock() }
        let fd = descriptor.withLock { $0 }
        guard fd >= 0 else { throw POSIXError(.ENOTCONN) }
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { Glibc_send(fd, $0.baseAddress, $0.count) }
            guard count > 0 else { throw POSIXError(.EPIPE) }
            sent += count
        }
    }

    private func read(_ fd: Int32) -> [UInt8]? {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let count = chunk.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
        return count > 0 ? Array(chunk[..<count]) : nil
    }

    private func connect(host: String, port: Int) -> Int32? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = Self.streamType
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "\(port)", &hints, &list) == 0, let info = list else { return nil }
        defer { freeaddrinfo(list) }
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return nil }
        #if canImport(Darwin)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
        guard Glibc_connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else {
            Glibc_close(fd)
            return nil
        }
        return fd
    }

    private static func frame(in buffer: [UInt8]) -> (Bool, UInt8, [UInt8], Int)? {
        guard buffer.count >= 2 else { return nil }
        var length = Int(buffer[1] & 127)
        var offset = 2
        if length == 126 {
            guard buffer.count >= 4 else { return nil }
            length = Int(buffer[2]) << 8 | Int(buffer[3])
            offset = 4
        } else if length == 127 {
            guard buffer.count >= 10 else { return nil }
            length = buffer[2..<10].reduce(0) { $0 << 8 | Int($1) }
            offset = 10
        }
        guard buffer.count >= offset + length else { return nil }
        return (buffer[0] & 0x80 != 0, buffer[0] & 15, Array(buffer[offset..<offset + length]), offset + length)
    }

    #if canImport(Glibc)
    private static let streamType = Int32(SOCK_STREAM.rawValue)
    #else
    private static let streamType = SOCK_STREAM
    #endif
}

private func Glibc_close(_ fd: Int32) { _ = close(fd) }
#if canImport(Glibc)
private func Glibc_send(_ fd: Int32, _ pointer: UnsafeRawPointer?, _ count: Int) -> Int { send(fd, pointer, count, Int32(MSG_NOSIGNAL)) }
#else
private func Glibc_send(_ fd: Int32, _ pointer: UnsafeRawPointer?, _ count: Int) -> Int { send(fd, pointer, count, 0) }
#endif
private func Glibc_connect(_ fd: Int32, _ address: UnsafeMutablePointer<sockaddr>?, _ length: socklen_t) -> Int32 { connect(fd, address, length) }

private extension [UInt8] {
    var headerEnd: Int {
        guard count >= 4 else { return -1 }
        for index in 0...(count - 4) where self[index] == 13 && self[index + 1] == 10 && self[index + 2] == 13 && self[index + 3] == 10 {
            return index
        }
        return -1
    }

    var containsHeaderEnd: Bool { headerEnd >= 0 }
}
