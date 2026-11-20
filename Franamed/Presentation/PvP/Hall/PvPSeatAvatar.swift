//
//  PvPSeatAvatar.swift
//  Franamed
//
//  Created by Claude on 20.11.2026.
//

import SwiftUI

/// What the ring around a player's avatar says.
/// Room: one segment per frame — misses red, the guessed frame green, the rest dim.
/// Duel: one arc for health, coloured green → orange → red.
struct PvPRingState: Equatable {
    enum Kind: Equatable {
        case frames(count: Int, misses: Int, solvedAt: Int?)
        case health(Double)
    }

    var kind: Kind
    var isAway = false
    var isGone = false
    var isOut = false
    var isSolved = false

    static func rival(_ rival: PvPRivalRow, isDuel: Bool) -> PvPRingState {
        let misses: Int
        var solvedAt: Int?
        switch rival.tone {
        case .thinking: misses = max(0, rival.frame - 1)
        case .solved:
            misses = max(0, rival.frame - 1)
            solvedAt = max(1, rival.frame)
        case .failed: misses = rival.frameCount
        case .out: misses = 0
        }
        let kind: Kind = isDuel ? .health(rival.health ?? 1)
            : .frames(count: max(rival.frameCount, 1), misses: misses, solvedAt: solvedAt)
        return PvPRingState(kind: kind, isAway: rival.isAway, isGone: rival.isGone,
                            isOut: rival.tone == .out && !rival.isGone, isSolved: rival.tone == .solved)
    }
}

struct PvPSeatAvatar: View {
    let avatar: PvPAvatar
    let ring: PvPRingState
    var size: CGFloat = 40
    /// Bumps on every miss so the avatar flashes red for a moment.
    var missToken = 0
    /// Duel frame strip under the avatar.
    var frames: (count: Int, misses: Int, solvedAt: Int?)?

    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let flashDuration = 0.4

    var body: some View {
        VStack(spacing: size * 0.12) {
            disc
            if let frames {
                PvPFrameStrip(count: frames.count, misses: frames.misses, solvedAt: frames.solvedAt)
                    .frame(width: size * 0.96, height: max(3, size * 0.08))
            }
        }
        .onChange(of: missToken) { _, _ in
            guard !reduceMotion else { return }
            flash = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.flashDuration))
                withAnimation(.easeOut(duration: 0.3)) { flash = false }
            }
        }
    }

    @ViewBuilder
    private var disc: some View {
        if ring.isGone {
            Circle()
                .strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: size, height: size)
        } else {
            ZStack {
                PvPRing(kind: ring.kind)
                    .opacity(ring.isAway ? 0.5 : 1)
                Circle()
                    .fill(.black)
                    .padding(size * 0.06)
                Circle()
                    .fill(PvPAvatarStyle.color(avatar.color).gradient)
                    .overlay {
                        Image(systemName: PvPAvatarStyle.symbol(avatar.icon))
                            .font(.system(size: size * 0.36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(size * 0.11)
                    .saturation(ring.isAway ? 0 : 1)
                    .brightness(ring.isAway ? -0.25 : 0)
            }
            .frame(width: size, height: size)
            .opacity(ring.isOut ? 0.45 : 1)
            .shadow(color: PvPHealth.red.opacity(flash ? 0.6 : 0), radius: size * 0.25)
            .overlay(alignment: .bottomTrailing) { badge }
            .animation(reduceMotion ? nil : .snappy, value: ring)
        }
    }

    @ViewBuilder
    private var badge: some View {
        let side = size * 0.32
        if ring.isAway {
            Image(systemName: "moon.fill")
                .font(.system(size: side * 0.52, weight: .bold))
                .foregroundStyle(Color(white: 0.92))
                .frame(width: side, height: side)
                .background(Color(white: 0.17), in: Circle())
                .overlay { Circle().strokeBorder(.black, lineWidth: size * 0.035) }
                .offset(x: size * 0.02, y: size * 0.02)
        } else if ring.isSolved {
            Image(systemName: "checkmark")
                .font(.system(size: side * 0.5, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: side, height: side)
                .background(PvPHealth.green, in: Circle())
                .overlay { Circle().strokeBorder(.black, lineWidth: size * 0.035) }
                .offset(x: size * 0.02, y: size * 0.02)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// The segmented ring. Segments start at twelve o'clock and run clockwise.
struct PvPRing: View {
    let kind: PvPRingState.Kind

    private static let dim = Color.white.opacity(0.15)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lineWidth = side * 0.06
            ZStack {
                switch kind {
                case let .frames(count, misses, solvedAt):
                    let gap = Angle.degrees(count >= 8 ? 5 : 7)
                    ForEach(0..<count, id: \.self) { index in
                        PvPRingSegment(index: index, count: count, gap: gap)
                            .stroke(color(index: index, misses: misses, solvedAt: solvedAt), lineWidth: lineWidth)
                    }
                case let .health(fraction):
                    Circle()
                        .inset(by: lineWidth / 2)
                        .stroke(Self.dim, lineWidth: lineWidth)
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: max(0, min(1, fraction)))
                        .stroke(PvPHealth.color(fraction), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: side, height: side)
        }
    }

    private func color(index: Int, misses: Int, solvedAt: Int?) -> Color {
        if index < misses { return PvPHealth.red }
        if let solvedAt {
            return index < solvedAt ? PvPHealth.green : PvPHealth.green.opacity(0.3)
        }
        return Self.dim
    }
}

private struct PvPRingSegment: Shape {
    let index: Int
    let count: Int
    let gap: Angle

    func path(in rect: CGRect) -> Path {
        let span = 360.0 / Double(count)
        let start = -90 + span * Double(index) + gap.degrees / 2
        let end = -90 + span * Double(index + 1) - gap.degrees / 2
        let lineInset = min(rect.width, rect.height) * 0.03
        let radius = min(rect.width, rect.height) / 2 - lineInset
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .degrees(count == 1 ? -90 : start), endAngle: .degrees(count == 1 ? 270 : end),
                    clockwise: false)
        return path
    }
}

/// Duel: a thin segmented strip under the avatar for frames.
struct PvPFrameStrip: View {
    let count: Int
    let misses: Int
    let solvedAt: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                Capsule()
                    .fill(color(index))
            }
        }
    }

    private func color(_ index: Int) -> Color {
        if index < misses { return PvPHealth.red }
        if let solvedAt, index < solvedAt { return PvPHealth.green }
        return .white.opacity(0.18)
    }
}

#if DEBUG
#Preview("Аватары в зале") {
    let blue = PvPAvatar(icon: "clapper", color: "blue")
    let orange = PvPAvatar(icon: "popcorn", color: "orange")
    VStack(spacing: 28) {
        HStack(spacing: 18) {
            PvPSeatAvatar(avatar: blue, ring: PvPRingState(kind: .frames(count: 6, misses: 0, solvedAt: nil)), size: 56)
            PvPSeatAvatar(avatar: blue, ring: PvPRingState(kind: .frames(count: 6, misses: 2, solvedAt: nil)), size: 56)
            PvPSeatAvatar(avatar: blue, ring: PvPRingState(kind: .frames(count: 6, misses: 2, solvedAt: 3), isSolved: true), size: 56)
            PvPSeatAvatar(avatar: blue, ring: PvPRingState(kind: .frames(count: 6, misses: 6, solvedAt: nil)), size: 56)
        }
        HStack(spacing: 18) {
            PvPSeatAvatar(avatar: blue, ring: PvPRingState(kind: .frames(count: 6, misses: 2, solvedAt: nil), isAway: true), size: 56)
            PvPSeatAvatar(avatar: blue, ring: PvPRingState(kind: .frames(count: 6, misses: 0, solvedAt: nil), isGone: true), size: 56)
            PvPSeatAvatar(avatar: orange, ring: PvPRingState(kind: .health(1)), size: 56, frames: (6, 1, 2))
            PvPSeatAvatar(avatar: orange, ring: PvPRingState(kind: .health(0.35)), size: 56, frames: (6, 3, nil))
            PvPSeatAvatar(avatar: orange, ring: PvPRingState(kind: .health(0.1)), size: 56)
        }
    }
    .padding()
    .background(.black)
}
#endif
