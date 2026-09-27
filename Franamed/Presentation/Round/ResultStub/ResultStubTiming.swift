//
//  ResultStubTiming.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import SwiftUI

enum ResultStubTiming {
    static let arrival = Spring(response: 0.5, dampingRatio: 0.72)
    static let slideDuration = 0.42
    static let settleAfterContact: TimeInterval = 0.25
    static let firstContact: TimeInterval = {
        var time: TimeInterval = 0
        while time < 2, arrival.value(target: 1.0, time: time) < 1 { time += 0.001 }
        return time
    }()
}
