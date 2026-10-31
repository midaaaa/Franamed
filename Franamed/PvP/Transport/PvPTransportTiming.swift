//
//  PvPTransportTiming.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

struct PvPTransportTiming: Sendable {
    var ping: Duration
    var silence: Duration
    var connectTimeout: Duration
    var reconnectDelay: Duration
    var failuresBeforePolling: Int
    var attemptsWithoutResume: Int
    var poll: Duration
    var pollTimeout: Duration
    var socketRetry: Duration
    var burst: Int
    var refill: Duration

    static let `default` = PvPTransportTiming(
        ping: .seconds(10),
        silence: .seconds(25),
        connectTimeout: .seconds(10),
        reconnectDelay: .milliseconds(500),
        failuresBeforePolling: 2,
        attemptsWithoutResume: 6,
        poll: .seconds(2),
        pollTimeout: .seconds(10),
        socketRetry: .seconds(30),
        burst: 20,
        refill: .seconds(2)
    )
}
