//
//  TicketTearConfig.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import SwiftUI

nonisolated struct TicketTearConfig: Sendable, Equatable {

    // MARK: Stub

    var stubSide: StubSide = .trailing
    var stubExtent: CGFloat = 104

    // MARK: Perforation pattern

    var pitch: CGFloat = 15
    var perfEndInset: CGFloat = 8
    var holeFraction: CGFloat = 0.66
    var holeHalfWidth: CGFloat = 1.7
    var slotCorner: CGFloat = 0.45
    var tearJitter: CGFloat = 1.2
    var tornSoftness: CGFloat = 0.45
    var tornGap: CGFloat = 1.0

    // MARK: Tear effort

    var breakStretch: CGFloat = 0.6
    var stretchScale: CGFloat = 0.42
    var creepFraction: CGFloat = 0.7
    var neckFraction: CGFloat = 0.86
    var crackWidth: CGFloat = 0.38

    // MARK: Curl

    var tightestCurl: CGFloat = 34

    // MARK: Gesture

    var grabDepth: CGFloat = 48
    var tearGain: CGFloat = 1.0

    // MARK: Timing

    var gracePeriod: TimeInterval = 0.7
    var relaxDuration: TimeInterval = 0.6

    // MARK: Detach

    var detachFlightDuration: TimeInterval = 0.34
    var detachFlightDistance: CGFloat = 0
    var detachFadeFraction: Double = 0.45
    var detachPushDelay: TimeInterval = 0.1

    // MARK: Return

    var returnStyle: TearReturnStyle = .curled
    var returnFlightDuration: TimeInterval = 0.42
    var returnZipDuration: TimeInterval = 0.45
    var returnFlightDistance: CGFloat = 0
    var returnFadeFraction: Double = 0.35
    var returnFromStart: Bool = false

    // MARK: Look

    var canvasPadding: CGFloat = 96
    var sheen: CGFloat = 0.30
    var backColor: Color = Color(red: 0.965, green: 0.950, blue: 0.925)
    var showsFrameRate: Bool = false
    var showsGrabZone: Bool = false

    // MARK: Отладочные тумблеры производительности

    var showsMesh: Bool = true
    var multisampling: Bool = true
    var opaqueLayerProbe: Bool = false

    init() {}
}
