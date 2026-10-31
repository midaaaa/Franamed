//
//  PvPWebSocket.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

enum PvPSocketFrame: Sendable, Equatable {
    case text(String)
    case closed(code: Int?, reason: String?, status: Int?)
}

protocol PvPWebSocket: Sendable {
    func receive() async -> PvPSocketFrame
    func send(_ text: String) async throws
    func close(code: Int)
}

protocol PvPWebSocketFactory: Sendable {
    func open(_ request: URLRequest) -> any PvPWebSocket
}

// MARK: - URLSession

struct PvPURLSessionWebSockets: PvPWebSocketFactory {
    let session: URLSession

    func open(_ request: URLRequest) -> any PvPWebSocket {
        let task = session.webSocketTask(with: request)
        task.resume()
        return PvPURLSessionWebSocket(task: task)
    }
}

final class PvPURLSessionWebSocket: PvPWebSocket {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func receive() async -> PvPSocketFrame {
        do {
            switch try await task.receive() {
            case let .string(text): return .text(text)
            case let .data(data): return .text(String(decoding: data, as: UTF8.self))
            @unknown default: return .text("")
            }
        } catch {
            let code = task.closeCode == .invalid ? nil : task.closeCode.rawValue
            return .closed(
                code: code,
                reason: task.closeReason.flatMap { String(data: $0, encoding: .utf8) },
                status: (task.response as? HTTPURLResponse)?.statusCode
            )
        }
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func close(code: Int) {
        task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil)
    }
}
