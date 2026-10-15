//
//  HallPhoneScreen.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.10.2026.
//

import QuartzCore

struct HallPhoneScreen {
    struct Pictures: Sendable {
        var app: HallPicture?
        var turnedApp: HallPicture?
        var notice: HallPicture?
    }

    struct Frame: Sendable {
        let app: HallPicture?
        let otherApp: HallPicture?
        let notice: HallPicture?
        let open: Float
        let glow: Float
    }

    private enum Notice {
        case waitingForRest
        case lighting(for: CFTimeInterval)
        case lit(until: CFTimeInterval)
    }

    private static let openResponse: Float = 0.5
    private static let glowResponse: Float = 0.3
    private static let noticeDuration: CFTimeInterval = 8
    private static let rewakeDuration: CFTimeInterval = 2.5
    private static let restRaise: Float = 0.02

    private(set) var isAppOn = false
    private var isDismissed = false
    private var pictures = Pictures()
    private var open = HallPhone.Spring(SIMD2<Float>.zero, response: openResponse)
    private var glow = HallPhone.Spring(SIMD2<Float>.zero, response: glowResponse)
    private var notice: Notice?

    var isSettled: Bool {
        notice == nil && open.isSettled(within: 0.002) && glow.isSettled(within: 0.002)
    }

    func frame(isTurned: Bool) -> Frame {
        Frame(app: isTurned ? pictures.turnedApp : pictures.app, otherApp: isTurned ? pictures.app : pictures.turnedApp,
              notice: pictures.notice, open: min(max(open.value.x, 0), 1.05), glow: min(max(glow.value.x, 0), 1))
    }

    mutating func setPictures(_ next: Pictures) {
        pictures = next
    }

    mutating func setNotice(_ picture: HallPicture?) {
        pictures.notice = picture
    }

    mutating func openApp(isRaised: Bool) {
        isAppOn = true
        isDismissed = false
        if isRaised {
            open.target = SIMD2(1, 0)
        } else {
            light(for: Self.noticeDuration)
        }
    }

    mutating func dismissApp() {
        guard isAppOn else { return }
        isAppOn = false
        isDismissed = true
        open.target = .zero
    }

    mutating func closeApp(isRaised: Bool) {
        isAppOn = false
        isDismissed = false
        notice = nil
        open.target = .zero
        glow.target = .zero
        if !isRaised { open = HallPhone.Spring(.zero, response: Self.openResponse) }
    }

    mutating func phoneRaised() {
        glow.target = .zero
        notice = nil
        guard isDismissed else { return }
        isDismissed = false
        isAppOn = true
        open.target = SIMD2(1, 0)
    }

    mutating func phoneLowered() -> Bool {
        guard isDismissed else { return false }
        notice = .waitingForRest
        return true
    }

    mutating func step(_ dt: Float, at time: CFTimeInterval, raise: Float) {
        open.step(dt)
        glow.step(dt)
        switch notice {
        case .waitingForRest where raise < Self.restRaise:
            isDismissed = false
            isAppOn = true
            light(for: Self.rewakeDuration)
        case .lighting(let duration):
            notice = .lit(until: time + duration)
        case .lit(let until) where time >= until:
            glow.target = .zero
            notice = nil
        default:
            break
        }
    }

    private mutating func light(for duration: CFTimeInterval) {
        open = HallPhone.Spring(SIMD2(1, 0), response: Self.openResponse)
        glow.target = SIMD2(1, 0)
        notice = .lighting(for: duration)
    }
}
