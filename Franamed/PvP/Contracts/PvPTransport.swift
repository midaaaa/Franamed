//
//  PvPTransport.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

enum PvPCredential: Sendable, Equatable {
    case ticket(String)
    case resume(String)
}

enum PvPLinkMode: Sendable, Equatable {
    case connecting
    case socket
    case reconnecting
    case polling
}

enum PvPTransportClosure: Sendable, Equatable {
    case socket(code: Int, reason: String?)
    case refused(status: Int, code: String)
    case cancelled

    var closeCode: PvPCloseCode? {
        if case let .socket(code, _) = self { return PvPCloseCode(rawValue: code) }
        return nil
    }
}

enum PvPTransportEvent: Sendable {
    case message(PvPEnvelope)
    case link(PvPLinkMode)
    case closed(PvPTransportClosure)
}

protocol PvPTransport: Sendable {
    var events: AsyncStream<PvPTransportEvent> { get }

    func connect(to socketURL: URL, credential: PvPCredential, lastSeq: Int?) async
    func send(_ message: PvPClientMessage) async
    func close() async
}
