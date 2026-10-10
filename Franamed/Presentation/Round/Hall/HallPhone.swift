//
//  HallPhone.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 08.10.2026.
//

import CoreGraphics
import QuartzCore
import simd
import UIKit

final class HallPhone: @unchecked Sendable {
    struct Settings: Equatable, Sendable {
        var aim: Float = 0.6
        var width: Float = 0.75
        var isPortrait = false
        var showsGrid = false
        var isWide = false
        var color = SIMD3<Float>(0.62, 0.6, 0.56)
        var slowFinder = true
        var bloom: Float = 0
        var screenBloom: Float = 0

        static let aspect: Float = 146.6 / 70.6
        static let bezel: Float = 0.039
        static let zoomStops: [Float] = [1, 2, 3]
        static let startZoom: Float = 2

        func size(viewWidth: Float) -> SIMD2<Float> {
            let long = viewWidth * width
            return isPortrait ? SIMD2(long / Self.aspect, long) : SIMD2(long, long / Self.aspect)
        }
    }

    struct Pose: Sendable {
        let point: SIMD2<Float>
        let lensPoint: SIMD2<Float>
        let raise: Float
        let zoom: Float
        let roll: Float
        let settings: Settings
        let chrome: HallPicture?
        let turnedChrome: HallPicture?
        let isTurning: Bool
        let layout: Layout
    }

    struct Geometry: Equatable, Sendable {
        var view: SIMD2<Float>
        var origin: SIMD2<Float>
        var screen: SIMD2<Float>
        var corner: Float
    }

    struct Layout: Sendable {
        let origin: SIMD2<Float>
        let view: SIMD2<Float>
        let screen: SIMD2<Float>
        let phone: SIMD2<Float>
        let travelX: Float
        let yLow: Float
        let yHigh: Float
        let room: Float
        let rangeX: Float
        let lift: Float
        let areaRadius: Float

        private static let inset: Float = 16
        private static let edge: Float = 0.04
        private static let fineCenter: Float = 0.6
        private static let give: Float = 8
        private static let cornerGive: Float = 3
        private static let overshoot: Float = 24
        private static let bodyRadius: Float = 0.155
        private static let liftShare: Float = 0.2
        private static let cornerPower: Float = 4
        static let cornerReach: Float = 2.6

        init(settings: Settings, geometry: Geometry, roll: Float, zoom: Float) {
            origin = geometry.origin
            view = geometry.view
            screen = geometry.screen
            let full = settings.size(viewWidth: view.x)
            let turn = SIMD2(abs(cos(roll)), abs(sin(roll)))
            phone = turn.x * full + turn.y * SIMD2(full.y, full.x)
            travelX = max(screen.x / 2 - Self.inset - phone.x / 2, 6)
            lift = Self.liftShare * full.min()
            yHigh = screen.y - Self.inset - phone.y / 2
            yLow = min(max(Self.inset + phone.y / 2, origin.y + lift), yHigh)
            areaRadius = max(geometry.corner - Self.inset, 0)
            let halfRoom = min(travelX, (yHigh - yLow) / 2)
            room = min(max(areaRadius - Self.bodyRadius * full.min(), 0) * Self.cornerReach, halfRoom)

            let border = 2 * Settings.bezel * full.min()
            let upright = (full.min() - border) / 2, sideways = (full.max() - border) / 2
            let own = settings.isPortrait ? upright : sideways
            let other = settings.isPortrait ? sideways : upright
            let k = max(zoom, 1) * (settings.isWide ? (16.0 / 9) / (4.0 / 3) : 1)
            let finderHalf = (turn.x * own + turn.y * other) / k
            rangeX = max(view.x / 2 + Self.edge * view.x - finderHalf, 0)
        }

        var areaLow: SIMD2<Float> { SIMD2(repeating: Self.inset) }
        var areaHigh: SIMD2<Float> { screen - Self.inset }

        func phonePoint(_ state: SIMD2<Float>) -> SIMD2<Float> {
            let parts = phoneParts(state)
            return parts.inner + parts.give
        }

        func phoneParts(_ state: SIMD2<Float>) -> (inner: SIMD2<Float>, give: SIMD2<Float>) {
            let raw = SIMD2(screen.x / 2 + state.x * travelX, state.y)
            let (inner, corner) = settle(raw)
            let beyond = simd_length(raw - inner)
            guard beyond > 0 else { return (raw, .zero) }
            let give = Self.give - (Self.give - Self.cornerGive) * corner
            return (inner, (raw - inner) * (give * (1 - exp(-beyond / give)) / beyond))
        }

        private func settle(_ point: SIMD2<Float>) -> (inner: SIMD2<Float>, corner: Float) {
            let low = SIMD2(screen.x / 2 - travelX, yLow) + room
            let high = SIMD2(screen.x / 2 + travelX, yHigh) - room
            let core = simd_clamp(point, low, simd_max(low, high))
            let out = point - core
            let length = Self.cornerLength(out)
            guard length > room else { return (point, 0) }
            let corner = smoothstep(0, 0.35, min(abs(out.x), abs(out.y)) / length)
            return (core + out * (room / length), corner)
        }

        static func cornerLength(_ v: SIMD2<Float>) -> Float {
            let a = abs(v)
            return pow(pow(a.x, cornerPower) + pow(a.y, cornerPower), 1 / cornerPower)
        }

        private func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
            let t = min(max((x - a) / (b - a), 0), 1)
            return t * t * (3 - 2 * t)
        }

        func reach(_ state: SIMD2<Float>) -> Float {
            reach(at: phonePoint(state))
        }

        private func reach(at point: SIMD2<Float>) -> Float {
            min(max((point.x - screen.x / 2) / travelX, -1), 1)
        }

        func target(_ state: SIMD2<Float>) -> SIMD2<Float> {
            let point = phonePoint(state)
            let u = reach(at: point)
            let beyond = point.x - screen.x / 2 - u * travelX
            let x = origin.x + view.x / 2 + (Self.fineCenter * u + (1 - Self.fineCenter) * u * u * u) * rangeX + beyond
            let y = point.y - lift
            return SIMD2(x, min(max(y, origin.y), origin.y + view.y))
        }

        func state(at point: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2((point.x - screen.x / 2) / travelX, point.y)
        }

        func limited(_ state: SIMD2<Float>) -> SIMD2<Float> {
            let raw = SIMD2(screen.x / 2 + state.x * travelX, state.y)
            let bound = settle(raw).inner
            let out = raw - bound
            let length = simd_length(out)
            guard length > Self.overshoot else { return state }
            return self.state(at: bound + out * (Self.overshoot / length))
        }

        func clamped(_ state: SIMD2<Float>) -> SIMD2<Float> {
            let edged = SIMD2(min(max(state.x, -1), 1), min(max(state.y, yLow), yHigh))
            return self.state(at: settle(SIMD2(screen.x / 2 + edged.x * travelX, edged.y)).inner)
        }

        func grip(at finger: SIMD2<Float>, settings: Settings) -> SIMD2<Float> {
            let full = settings.size(viewWidth: view.x)
            let offset = settings.isPortrait ? SIMD2(0, 0.38 * full.y) : SIMD2(0.36 * full.x, 0.1 * full.y)
            return state(at: finger - offset)
        }
    }

    private struct Spring<Value: SIMD> where Value.Scalar == Float {
        var value: Value
        var velocity: Value = .zero
        var target: Value
        let response: Float

        init(_ value: Value, response: Float) {
            self.value = value
            self.target = value
            self.response = response
        }

        mutating func step(_ dt: Float) {
            let omega = 2 * Float.pi / response
            let offset = value - target
            let b = velocity + omega * offset
            let decay = exp(-omega * dt)
            value = target + (offset + b * dt) * decay
            velocity = (velocity - omega * b * dt) * decay
        }

        func isSettled(within tolerance: Value) -> Bool {
            let offset = value - target
            return all(offset * offset .< tolerance * tolerance) && all(velocity * velocity .< tolerance * tolerance * 100)
        }

        func isSettled(within tolerance: Float) -> Bool {
            isSettled(within: Value(repeating: tolerance))
        }
    }

    private static let followResponse: Float = 0.12
    private static let raiseResponse: Float = 0.42
    private static let lensResponse: Float = 0.1
    private static let zoomResponse: Float = 0.25
    private static let rollResponse: Float = 0.4
    private static let flingSpeed: CGFloat = 900

    private let lock = NSLock()
    private var _settings = Settings()
    private var _onChange: (() -> Void)?
    private var chromes: [HallPhoneChrome.Key: HallPicture] = [:]
    private var point = Spring(SIMD2<Float>.zero, response: followResponse)
    private var lens = Spring(SIMD2<Float>.zero, response: lensResponse)
    private var raise = Spring(SIMD2<Float>.zero, response: raiseResponse)
    private var zoom = Spring(SIMD2<Float>(2, 0), response: zoomResponse)
    private var roll = Spring(SIMD2<Float>.zero, response: rollResponse)
    private var rest: SIMD2<Float>?
    private var geometry: Geometry?
    private var isRaised = false
    private var stowed: SIMD2<Float>?
    private var shownLayout: Layout?
    private var _isLocked = false
    private var shown: SIMD2<Float>?
    private var twistSign: Float?
    private var dragStart: SIMD2<Float>?
    private var pinchStart: Float?
    private var lastTime: CFTimeInterval?

    var settings: Settings {
        get { lock.withLock { _settings } }
        set {
            let changed = lock.withLock {
                let old = _settings
                _settings = newValue
                if old.isPortrait != newValue.isPortrait {
                    roll.value += SIMD2(Self.turnOffset(toPortrait: newValue.isPortrait), 0)
                    roll.target = .zero
                }
                return old != newValue
            }
            if changed { notify() }
        }
    }

    var onChange: (() -> Void)? {
        get { lock.withLock { _onChange } }
        set { lock.withLock { _onChange = newValue } }
    }

    var isHeld: Bool { lock.withLock { isRaised } }

    var isLocked: Bool {
        get { lock.withLock { _isLocked } }
        set {
            lock.withLock {
                _isLocked = newValue
                if newValue { stowed = nil }
            }
            if newValue { lower() }
        }
    }

    nonisolated(unsafe) var onHeldChange: (@MainActor (Bool) -> Void)?

    func setChrome(_ picture: HallPicture, for key: HallPhoneChrome.Key) {
        lock.withLock { chromes[key] = picture }
        notify()
    }

    func setGeometry(_ next: Geometry) {
        lock.withLock { if geometry != next { geometry = next } }
    }

    private func currentLayout() -> Layout? {
        geometry.map { Layout(settings: _settings, geometry: $0, roll: roll.value.x, zoom: zoom.value.x) }
    }

    func setRest(_ point: CGPoint) {
        let changed = lock.withLock {
            let next = SIMD2(point)
            guard rest != next else { return false }
            if rest == nil { zoom = Spring(SIMD2(Settings.startZoom, 0), response: Self.zoomResponse) }
            rest = next
            return true
        }
        if changed { notify() }
    }

    func contains(_ location: CGPoint) -> Bool {
        lock.withLock {
            let p = SIMD2(location)
            if isRaised {
                guard let shown, let layout = shownLayout else { return false }
                return all(abs(p - shown) .<= layout.phone / 2 + 12)
            }
            guard let rest else { return false }
            return all(abs(p - rest) .<= SIMD2(44, 44))
        }
    }

    func raise(to home: CGPoint) {
        raise { $0.state(at: SIMD2(home)) }
    }

    func raise(grabbing finger: CGPoint) {
        raise { [_settings] in $0.grip(at: SIMD2(finger), settings: _settings) }
    }

    private func raise(state: SIMD2<Float>) {
        raise { _ in state }
    }

    private func raise(_ destination: (Layout) -> SIMD2<Float>) {
        let raises = lock.withLock {
            guard !_isLocked, let layout = currentLayout() else { return false }
            stowed = nil
            if !isRaised, raise.value.x < 0.05 {
                let start = layout.state(at: rest ?? SIMD2(layout.view / 2))
                point = Spring(start, response: Self.followResponse)
                lens = Spring(start, response: Self.lensResponse)
            }
            point.target = layout.clamped(destination(layout))
            raise.target = SIMD2(1, 0)
            isRaised = true
            return true
        }
        guard raises else { return }
        notify()
        MainActor.assumeIsolated { onHeldChange?(true) }
    }

    func lower(animated: Bool = true) {
        lock.withLock {
            stowed = nil
            if !animated { raise = Spring(.zero, response: Self.raiseResponse) }
            isRaised = false
            dragStart = nil
            pinchStart = nil
            raise.target = .zero
        }
        notify()
        MainActor.assumeIsolated { onHeldChange?(false) }
    }

    func show(_ point: SIMD2<Float>, layout: Layout) {
        lock.withLock {
            shown = point
            shownLayout = layout
        }
    }

    func twist(_ rotation: CGFloat) {
        lock.withLock {
            let sign = twistSign ?? -Self.turnOffset(toPortrait: !_settings.isPortrait) / (.pi / 2)
            twistSign = sign
            let along = -Float(rotation) * sign
            let limited = along < 0 ? max(along * 0.25, -0.15) : min(along, .pi / 2)
            roll.target = SIMD2(limited * sign, 0)
        }
        notify()
    }

    func endTwist() -> Bool {
        let turns = lock.withLock {
            defer { twistSign = nil }
            guard let twistSign else { return false }
            let turns = roll.target.x * twistSign > Self.twistThreshold
            if !turns { roll.target = .zero }
            return turns
        }
        notify()
        return turns
    }

    private static let twistThreshold: Float = 0.5

    private static func turnOffset(toPortrait: Bool) -> Float {
        toPortrait ? .pi / 2 : -.pi / 2
    }

    func stow() {
        let target: SIMD2<Float>? = lock.withLock { isRaised ? point.target : nil }
        guard let target else { return }
        lower()
        lock.withLock { stowed = target }
    }

    func unstow() {
        let target: SIMD2<Float>? = lock.withLock {
            defer { stowed = nil }
            return stowed
        }
        guard let target else { return }
        raise(state: target)
    }

    func drag(by translation: CGPoint) {
        lock.withLock {
            guard let layout = currentLayout() else { return }
            let start = dragStart ?? layout.clamped(point.target)
            let move = SIMD2(Float(translation.x) / layout.travelX, Float(translation.y))
            let target = layout.limited(start + move)
            dragStart = target - move
            point.target = target
        }
        notify()
    }

    func endDrag(velocity: CGPoint) {
        let lowers = lock.withLock {
            dragStart = nil
            guard let layout = currentLayout() else { return false }
            let lowers = velocity.y > Self.flingSpeed || point.target.y > layout.yHigh + Self.dropDistance
            if !lowers { point.target = layout.clamped(point.target) }
            return lowers
        }
        if lowers { lower() } else { notify() }
    }

    private static let dropDistance: Float = 60
    private static let stillPoints: Float = 0.02
    private static let wakeStep: Float = 1.0 / 120

    func pinch(_ scale: CGFloat, ended: Bool) {
        lock.withLock {
            let start = pinchStart ?? zoom.target.x
            pinchStart = ended ? nil : start
            var next = min(max(start * Float(scale), 1), 3)
            if ended, let stop = Settings.zoomStops.min(by: { abs($0 - next) < abs($1 - next) }), abs(stop - next) < 0.2 {
                next = stop
            }
            zoom.target = SIMD2(next, 0)
        }
        notify()
    }

    func cycleZoom() {
        lock.withLock {
            let current = zoom.target.x
            let next = Settings.zoomStops.first { $0 > current + 0.05 } ?? Settings.zoomStops[0]
            zoom.target = SIMD2(next, 0)
        }
        notify()
    }


    func pose(at time: CFTimeInterval) -> (pose: Pose?, isAnimating: Bool) {
        lock.withLock {
            guard rest != nil, let geometry else { return (nil, false) }
            let dt = lastTime.map { Float(min(max(time - $0, 0), 0.05)) } ?? Self.wakeStep
            lastTime = time
            point.step(dt)
            raise.step(dt)
            zoom.step(dt)
            roll.step(dt)
            lens.target = point.value
            lens.step(dt)
            let layout = Layout(settings: _settings, geometry: geometry, roll: roll.value.x, zoom: zoom.value.x)
            let still = SIMD2(Self.stillPoints / layout.travelX, Self.stillPoints)
            let isTurning = !roll.isSettled(within: 0.002) || !zoom.isSettled(within: 0.002)
            let isAnimating = isTurning || !point.isSettled(within: still) || !lens.isSettled(within: still)
                || !raise.isSettled(within: 0.001)
            if !isAnimating { lastTime = nil }
            let stop = Settings.zoomStops.min { abs($0 - zoom.value.x) < abs($1 - zoom.value.x) } ?? 1
            let chrome = chromes[HallPhoneChrome.Key(isWide: _settings.isWide, scale: stop, isTurned: !_settings.isPortrait)]
            let turnedChrome = chromes[HallPhoneChrome.Key(isWide: _settings.isWide, scale: stop,
                                                           isTurned: _settings.isPortrait)]
            let pose = Pose(point: point.value, lensPoint: lens.value,
                            raise: min(max(raise.value.x, 0), 1), zoom: zoom.value.x, roll: roll.value.x,
                            settings: _settings, chrome: chrome, turnedChrome: turnedChrome,
                            isTurning: isTurning, layout: layout)
            return (pose, isAnimating)
        }
    }

    private func notify() {
        onChange?()
    }
}

extension SIMD2 where Scalar == Float {
    init(_ point: CGPoint) {
        self.init(Float(point.x), Float(point.y))
    }
}
