//
//  PvPScreenCanvas.swift
//  Franamed
//
//  Created by Claude on 20.11.2026.
//

import Combine
import SwiftUI
import UIKit

/// What the cinema screen shows between frames: the round countdown and the round results.
enum PvPScreenScene: Equatable {
    case countdown(PvPCountdownScene)
    case results(PvPRevealScreen)
    case final(PvPFinalScreen)

    /// Scenes with the same key continue one animation; a new key restarts the clock.
    var key: String {
        switch self {
        case let .countdown(scene): "countdown-\(scene.film)-\(scene.isResume)"
        case let .results(reveal): "results-\(reveal.film)"
        case let .final(final): "final-\(final.title)-\(final.standings.count)"
        }
    }
}

struct PvPCountdownScene: Equatable {
    let value: Int
    let film: Int
    let title: String
    let detail: String?
    var isResume = false
}

/// Renders the scene into a picture for the Metal hall screen and samples its light for the seats.
/// It draws through `ImageRenderer`, so every animation here is driven by an explicit clock.
@MainActor
final class PvPScreenCanvas: ObservableObject {
    @Published private(set) var picture: HallPicture?
    @Published private(set) var light: HallFrameSample = .dark

    var scene: PvPScreenScene?
    var pointSize: CGSize = .zero
    var pixelWidth: CGFloat = 0

    static let designSize = CGSize(width: 640, height: 360)
    /// About 1000 px wide is plenty for a screen seen from the seats, and keeps each frame cheap.
    private static let maxScale: CGFloat = 1.6
    private static let animatedInterval = Duration.milliseconds(33)
    private static let idleInterval = Duration.milliseconds(120)

    private var renderedFingerprint: String?

    func clear() {
        picture = nil
        light = .dark
        renderedFingerprint = nil
    }

    /// Runs while one scene key is on screen; the task is restarted when the key changes.
    func run() async {
        let start = Date.now
        var lastValue: Int?
        var valueChangedAt = start
        renderedFingerprint = nil
        while !Task.isCancelled {
            guard let scene, pixelWidth > 0 else {
                try? await Task.sleep(for: Self.idleInterval)
                continue
            }
            let now = Date.now
            var clock = now.timeIntervalSince(start)
            var previous: Int?
            if case let .countdown(countdown) = scene {
                if lastValue != countdown.value {
                    previous = lastValue
                    lastValue = countdown.value
                    valueChangedAt = now
                }
                clock = now.timeIntervalSince(valueChangedAt)
                previous = previous ?? (clock < PvPScreenArt.digitRoll ? countdown.value + 1 : nil)
            }
            let animating = PvPScreenArt.isAnimating(scene, clock: clock)
            let fingerprint = PvPScreenArt.fingerprint(scene, clock: animating ? clock : .infinity)
            if fingerprint != renderedFingerprint {
                await render(scene, clock: clock, previous: previous)
                renderedFingerprint = fingerprint
            }
            try? await Task.sleep(for: animating ? Self.animatedInterval : Self.idleInterval)
        }
    }

    private func render(_ scene: PvPScreenScene, clock: TimeInterval, previous: Int?) async {
        let content = PvPScreenArt(scene: scene, clock: clock, previousValue: previous)
            .frame(width: Self.designSize.width, height: Self.designSize.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = min(Self.maxScale, max(1, pixelWidth / Self.designSize.width))
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return }
        async let sample = HallFrameSample.make(image)
        async let made = HallPicture.make(image)
        let (light, picture) = await (sample, made)
        guard !Task.isCancelled else { return }
        if let picture { self.picture = picture }
        if let light { self.light = light }
    }
}

// MARK: - Art

/// The screen content at a moment in time. Pure function of the scene and the clock.
struct PvPScreenArt: View {
    let scene: PvPScreenScene
    let clock: TimeInterval
    var previousValue: Int?

    static let digitRoll: TimeInterval = 0.42
    static let roomPoints: TimeInterval = 0.9
    static let roomSums: TimeInterval = 2.1
    static let roomOrder: TimeInterval = 2.9
    static let duelApproach: TimeInterval = 0.9
    static let duelClash: TimeInterval = 1.5
    static let duelHit: TimeInterval = 2.6
    static let podiumRise: TimeInterval = 1.6

    static func isAnimating(_ scene: PvPScreenScene, clock: TimeInterval) -> Bool {
        switch scene {
        case .countdown: clock < digitRoll + 0.1
        case let .results(reveal): clock < (reveal.clash == nil ? roomOrder : duelHit) + 0.1
        case .final: clock < podiumRise + 0.1
        }
    }

    /// Changes only when the picture would change, so idle scenes are not re-rendered.
    static func fingerprint(_ scene: PvPScreenScene, clock: TimeInterval) -> String {
        switch scene {
        case let .countdown(countdown):
            "\(countdown.value)|\(countdown.title)|\(countdown.detail ?? "")|\(clock)"
        case let .results(reveal):
            "\(reveal.film)|\(reveal.nextTimer?.text ?? "")|\(clock)"
        case let .final(final):
            "\(final.title)|\(final.standings.map(\.score))|\(clock)"
        }
    }

    var body: some View {
        ZStack {
            Color.black
            switch scene {
            case let .countdown(countdown):
                PvPCountdownArt(scene: countdown, clock: clock, previous: previousValue)
            case let .results(reveal):
                if let clash = reveal.clash {
                    PvPDuelResultsArt(reveal: reveal, clash: clash, clock: clock)
                } else {
                    PvPRoomResultsArt(reveal: reveal, clock: clock)
                }
            case let .final(final):
                PvPFinalArt(screen: final, clock: clock)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private func ease(_ t: Double) -> Double {
    let x = min(1, max(0, t))
    return 1 - pow(1 - x, 3)
}

private func phase(_ clock: TimeInterval, from: TimeInterval, to: TimeInterval) -> Double {
    guard to > from else { return clock >= to ? 1 : 0 }
    return min(1, max(0, (clock - from) / (to - from)))
}

// MARK: Countdown

private struct PvPCountdownArt: View {
    let scene: PvPCountdownScene
    let clock: TimeInterval
    let previous: Int?

    var body: some View {
        let roll = ease(clock / PvPScreenArt.digitRoll)
        ZStack {
            ZStack {
                if let previous, roll < 1 {
                    digit(previous)
                        .offset(y: -70 * roll)
                        .opacity(1 - roll)
                        .blur(radius: 8 * roll)
                }
                digit(scene.value)
                    .offset(y: 70 * (1 - roll))
                    .opacity(roll)
                    .blur(radius: 8 * (1 - roll))
            }
            .frame(width: 200, height: 170)
            .clipped()
            VStack {
                Text(scene.title.uppercased())
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if let detail = scene.detail {
                    Text(detail)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.vertical, 26)
        }
    }

    private func digit(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 150, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
    }
}

// MARK: Room results

private struct PvPRoomResultsArt: View {
    let reveal: PvPRevealScreen
    let clock: TimeInterval

    private static let rowHeight: CGFloat = 34
    private static let listTop: CGFloat = 62

    var body: some View {
        let order = ease(phase(clock, from: PvPScreenArt.roomSums, to: PvPScreenArt.roomOrder))
        let sums = ease(phase(clock, from: PvPScreenArt.roomPoints, to: PvPScreenArt.roomSums))
        let rows = Array(reveal.board.prefix(8))
        ZStack(alignment: .topLeading) {
            HStack {
                Text("ИТОГИ · \(reveal.title.uppercased())")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if let timer = reveal.nextTimer, let next = reveal.next {
                    Text("\(next) через \(timer.text)")
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 24)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let appear = ease(phase(clock, from: Double(index) * 0.07, to: Double(index) * 0.07 + 0.45))
                let place = Double(row.placeBefore) + Double(row.placeAfter - row.placeBefore) * order
                PvPBoardLine(row: row, sums: sums, order: order, appear: appear)
                    .frame(width: 572, height: Self.rowHeight - 4)
                    .offset(x: 34, y: Self.listTop + CGFloat(place - 1) * Self.rowHeight)
            }
        }
    }
}

private struct PvPBoardLine: View {
    let row: PvPBoardRow
    let sums: Double
    let order: Double
    let appear: Double

    var body: some View {
        let total = Double(row.before) + Double(row.after - row.before) * sums
        let shift = row.placeBefore - row.placeAfter
        HStack(spacing: 12) {
            Text("\(row.placeAfter)")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(order > 0.5 ? 0.9 : 0.35))
                .frame(width: 22, alignment: .trailing)
            PvPSeatAvatar(avatar: row.avatar,
                          ring: PvPRingState(kind: .frames(count: 1, misses: row.isSolved ? 0 : 1, solvedAt: row.isSolved ? 1 : nil)),
                          size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.isYou ? "\(row.name) · вы" : row.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(row.detail)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 8)
            Text(row.gained > 0 ? PvPScreenText.signed(row.gained) : "+0")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(row.gained > 0 ? PvPHealth.green : .white.opacity(0.35))
                .opacity(1 - sums * 0.65)
            Text(PvPScreenText.number(Int(total.rounded())))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .frame(width: 84, alignment: .trailing)
            Group {
                if shift != 0 {
                    Text(shift > 0 ? "▲\(shift)" : "▼\(-shift)")
                        .foregroundStyle(shift > 0 ? PvPHealth.green : PvPHealth.red)
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .frame(width: 30, alignment: .leading)
            .opacity(order)
        }
        .padding(.horizontal, 10)
        .foregroundStyle(.white)
        .background {
            if row.isYou {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.12))
            }
        }
        .opacity(appear)
        .offset(x: 18 * (1 - appear))
    }
}

// MARK: Duel results

private struct PvPDuelResultsArt: View {
    let reveal: PvPRevealScreen
    let clash: PvPDuelClash
    let clock: TimeInterval

    var body: some View {
        let approach = ease(phase(clock, from: 0.2, to: PvPScreenArt.duelApproach))
        let impact = phase(clock, from: PvPScreenArt.duelApproach, to: PvPScreenArt.duelClash)
        let hit = ease(phase(clock, from: PvPScreenArt.duelClash, to: PvPScreenArt.duelHit))
        let loserIsYou = clash.you.hpAfter < clash.you.hpBefore
        let hasDamage = clash.damage > 0
        ZStack {
            VStack {
                Text("ДУЭЛЬ · \(reveal.title.uppercased())")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if let timer = reveal.nextTimer, let next = reveal.next {
                    Text("\(next) через \(timer.text)")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.vertical, 22)

            side(clash.you, x: -190, hit: loserIsYou ? hit : 0)
            side(clash.rival, x: 190, hit: loserIsYou ? 0 : hit)

            // Points travel to the middle and collide.
            if impact < 1 {
                points(clash.you.points, from: -150, approach: approach)
                    .opacity(1 - impact)
                points(clash.rival.points, from: 150, approach: approach)
                    .opacity(1 - impact)
            }
            if clock >= PvPScreenArt.duelApproach {
                let fly = loserIsYou ? -190.0 : 190.0
                Text(hasDamage ? "−\(PvPScreenText.number(clash.damage))" : "0")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(hasDamage ? PvPHealth.red : .white.opacity(0.7))
                    .scaleEffect(1 + 0.25 * (1 - ease(impact)))
                    .offset(x: hasDamage ? fly * hit : 0, y: hasDamage ? -6 * hit : 0)
                    .opacity(hasDamage ? 1 - pow(hit, 3) : 1)
                if clash.multiplier > 1, hit < 0.2 {
                    Text("(\(max(clash.you.points, clash.rival.points)) − \(min(clash.you.points, clash.rival.points))) \(PvPScreenText.multiplier(clash.multiplier))")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .offset(y: 44)
                }
            }
        }
    }

    private func points(_ value: Int, from x: CGFloat, approach: Double) -> some View {
        Text("\(value)")
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .offset(x: x * (1 - approach))
            .opacity(approach > 0 ? 1 : 0)
    }

    private func side(_ side: PvPDuelClash.Side, x: CGFloat, hit: Double) -> some View {
        let maxHP = Double(max(clash.maxHP, 1))
        let hp = Double(side.hpBefore) + Double(side.hpAfter - side.hpBefore) * hit
        return VStack(spacing: 10) {
            PvPSeatAvatar(avatar: side.avatar, ring: PvPRingState(kind: .health(hp / maxHP)), size: 92)
                .shadow(color: PvPHealth.red.opacity(hit > 0 && hit < 1 ? 0.8 : 0), radius: 24)
            Text(side.isYou ? "Вы" : side.name)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
            Text("\(PvPScreenText.number(max(0, Int(hp.rounded())))) HP")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(PvPHealth.color(hp / maxHP))
            Text(side.detail)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white)
        .frame(width: 180)
        .offset(x: x, y: 6)
    }
}

// MARK: Final

/// The match result: a podium for the room, both health rings for a duel.
private struct PvPFinalArt: View {
    let screen: PvPFinalScreen
    let clock: TimeInterval

    private var tint: Color {
        switch screen.tone {
        case .win: PlaylistStyle.gold
        case .loss: PvPHealth.red
        case .draw, .neutral: .white
        }
    }

    var body: some View {
        let appear = ease(phase(clock, from: 0, to: 0.5))
        ZStack {
            VStack(spacing: 4) {
                Text(screen.title)
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(tint)
                    .scaleEffect(0.85 + 0.15 * appear)
                Text(screen.subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let duel = screen.duel {
                    duelRow(duel)
                } else {
                    podium
                }
                Spacer(minLength: 0)
                Text(screen.solvedLine.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.vertical, 24)
            .opacity(appear)
        }
    }

    private var podium: some View {
        let top = Array(screen.standings.prefix(3))
        let order = [1, 0, 2].filter { $0 < top.count }
        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(order, id: \.self) { index in
                let row = top[index]
                let height: CGFloat = [96, 64, 44][index]
                let rise = ease(phase(clock, from: 0.3 + Double(index) * 0.2, to: 1.1 + Double(index) * 0.2))
                VStack(spacing: 6) {
                    PvPSeatAvatar(avatar: row.avatar, ring: PvPRingState(kind: .health(1)), size: index == 0 ? 56 : 44)
                        .opacity(rise)
                    Text(row.isYou ? "Вы" : row.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(row.score)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(row.isYou ? tint.opacity(0.55) : .white.opacity(0.14))
                        Text("\(row.place)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .padding(.top, 6)
                    }
                    .frame(width: 120, height: height * rise)
                }
                .frame(width: 130)
            }
        }
        .foregroundStyle(.white)
    }

    private func duelRow(_ duel: PvPDuelBars) -> some View {
        HStack(spacing: 70) {
            ForEach([duel.you, duel.rival]) { bar in
                VStack(spacing: 8) {
                    PvPSeatAvatar(avatar: bar.avatar, ring: PvPRingState(kind: .health(bar.fraction)), size: 86)
                    Text(bar.isYou ? "Вы" : bar.name)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text("\(bar.text) HP")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(PvPHealth.color(bar.fraction))
                }
                .frame(width: 170)
            }
        }
        .foregroundStyle(.white)
    }
}

#if DEBUG
/// One frame of the cinema screen at a chosen moment of its animation.
private struct PvPScreenArtPreview: View {
    let scene: PvPScreenScene?
    let clock: TimeInterval
    var previous: Int?

    var body: some View {
        if let scene {
            PvPScreenArt(scene: scene, clock: clock, previousValue: previous)
                .frame(width: PvPScreenCanvas.designSize.width, height: PvPScreenCanvas.designSize.height)
                .clipShape(.rect(cornerRadius: 8))
                .padding()
                .background(.black)
        }
    }

    static func reveal(_ state: PvPMatchState) -> PvPScreenScene? { PvPPreview.reveal(state).map { .results($0) } }
    static func final(_ state: PvPMatchState) -> PvPScreenScene? { PvPPreview.final(state).map { .final($0) } }
}

private let previewCountdown = PvPScreenScene.countdown(PvPCountdownScene(value: 2, film: 1, title: "Фильм 1 из 5", detail: "Приготовьтесь"))

#Preview("Экран: отсчёт, цифра меняется") { PvPScreenArtPreview(scene: previewCountdown, clock: 0.15, previous: 3) }
#Preview("Экран: отсчёт, середина секунды") { PvPScreenArtPreview(scene: previewCountdown, clock: 0.6) }
#Preview("Экран: после паузы") {
    PvPScreenArtPreview(scene: .countdown(PvPCountdownScene(value: 1, film: 3, title: "Фильм 3 из 5", detail: "Продолжаем", isResume: true)), clock: 0.5)
}
#Preview("Экран: комната, 1. очки") { PvPScreenArtPreview(scene: PvPScreenArtPreview.reveal(PvPMatchFixtures.revealRoom), clock: 0.8) }
#Preview("Экран: комната, 2. суммы") { PvPScreenArtPreview(scene: PvPScreenArtPreview.reveal(PvPMatchFixtures.revealRoom), clock: 1.6) }
#Preview("Экран: комната, 3. порядок") { PvPScreenArtPreview(scene: PvPScreenArtPreview.reveal(PvPMatchFixtures.revealRoom), clock: 5) }
#Preview("Экран: дуэль, 1. очки") { PvPScreenArtPreview(scene: PvPScreenArtPreview.reveal(PvPMatchFixtures.revealDuel), clock: 0.6) }
#Preview("Экран: дуэль, 2. столкновение") { PvPScreenArtPreview(scene: PvPScreenArtPreview.reveal(PvPMatchFixtures.revealDuel), clock: 1.2) }
#Preview("Экран: дуэль, 3. урон") { PvPScreenArtPreview(scene: PvPScreenArtPreview.reveal(PvPMatchFixtures.revealDuel), clock: 5) }
#Preview("Экран: финал, комната") { PvPScreenArtPreview(scene: PvPScreenArtPreview.final(PvPMatchFixtures.finishedRoom), clock: 5) }
#Preview("Экран: финал, победа") { PvPScreenArtPreview(scene: PvPScreenArtPreview.final(PvPMatchFixtures.finishedVictory), clock: 5) }
#Preview("Экран: финал, поражение") { PvPScreenArtPreview(scene: PvPScreenArtPreview.final(PvPMatchFixtures.finishedDefeat), clock: 5) }
#Preview("Экран: финал, не состоялся") { PvPScreenArtPreview(scene: PvPScreenArtPreview.final(PvPMatchFixtures.finishedAbandoned), clock: 5) }
#endif
