//
//  HallPhoneChrome.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 08.10.2026.
//

import SwiftUI

struct HallPhoneChrome: View {
    struct Key: Hashable {
        let isWide: Bool
        let scale: Float
        let isTurned: Bool
    }

    let key: Key

    static let width: CGFloat = 300
    static let height: CGFloat = width * CGFloat((HallPhone.Settings.aspect - 2 * HallPhone.Settings.bezel)
        / (1 - 2 * HallPhone.Settings.bezel))

    private let w = Self.width
    private let yellow = Color(red: 1, green: 0.84, blue: 0.04)

    private var turn: Angle { .degrees(key.isTurned ? 90 : 0) }

    var body: some View {
        ZStack {
            topIcons
            zoomRow
            shutter
            modes
            bottomRow
        }
        .frame(width: Self.width, height: Self.height)
        .environment(\.colorScheme, .dark)
    }

    private var topIcons: some View {
        HStack {
            Image(systemName: "bolt.slash.fill").rotationEffect(turn)
            Spacer()
            Text(key.isWide ? "16:9" : "4:3")
                .font(.system(size: 0.034 * w, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 0.025 * w)
                .padding(.vertical, 0.008 * w)
                .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 0.004 * w))
                .rotationEffect(turn)
            Spacer()
            Image(systemName: "moon.fill").foregroundStyle(yellow).rotationEffect(turn)
        }
        .font(.system(size: 0.048 * w, weight: .regular))
        .foregroundStyle(.white)
        .padding(.horizontal, 0.09 * w)
        .frame(width: w)
        .position(x: w / 2, y: 0.21 * w)
    }

    private var zoomRow: some View {
        let stops = HallPhone.Settings.zoomStops
        let active = stops.min { abs($0 - key.scale) < abs($1 - key.scale) } ?? 1
        return HStack(spacing: 0.03 * w) {
            ForEach(stops, id: \.self) { stop in
                let isActive = stop == active
                Text(isActive ? "\(Int(stop))×" : "\(Int(stop))")
                    .font(.system(size: 0.032 * w, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isActive ? yellow : .white)
                    .frame(width: 0.085 * w, height: 0.085 * w)
                    .background(Circle().fill(.black.opacity(isActive ? 0.45 : 0)))
                    .rotationEffect(turn)
            }
        }
        .position(x: w / 2, y: Self.height - 0.627 * w)
    }

    private var modes: some View {
        let photo = 0.074 * w
        return ZStack {
            Capsule()
                .fill(.black.opacity(0.4))
                .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.003 * w))
                .frame(width: 0.39 * w, height: 0.122 * w)
            Capsule()
                .fill(.white.opacity(0.16))
                .frame(width: 0.22 * w, height: 0.1 * w)
                .offset(x: photo)
            Text("ФОТО").foregroundStyle(yellow).offset(x: photo)
            Text("ВИДЕО").foregroundStyle(.white.opacity(0.75)).offset(x: photo - 0.185 * w)
        }
        .font(.system(size: 0.031 * w, weight: .medium))
        .position(x: w / 2, y: Self.height - 0.148 * w)
    }

    private var shutter: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.55), lineWidth: 0.012 * w)
                .frame(width: 0.196 * w, height: 0.196 * w)
            Circle()
                .fill(.white)
                .frame(width: 0.166 * w, height: 0.166 * w)
        }
        .position(x: w / 2, y: Self.height - 0.39 * w)
    }

    private var bottomRow: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.003 * w)
                .frame(width: 0.122 * w, height: 0.122 * w)
                .offset(x: -0.352 * w)
            sideButton {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 0.045 * w, weight: .medium))
                    .rotationEffect(turn)
            }
            .offset(x: 0.352 * w)
        }
        .position(x: w / 2, y: Self.height - 0.148 * w)
    }

    private func sideButton(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .foregroundStyle(.white)
            .frame(width: 0.122 * w, height: 0.122 * w)
            .background(Circle().fill(.black.opacity(0.4)))
    }

    @MainActor
    static func picture(for key: Key) async -> HallPicture? {
        let renderer = ImageRenderer(content: HallPhoneChrome(key: key))
        renderer.scale = 3
        renderer.isOpaque = false
        guard let image = renderer.uiImage else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        format.preferredRange = .standard
        let flattened = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
        return await HallPicture.make(flattened)
    }
}

#Preview("Phone chrome — 4:3, ×2") {
    HallPhoneChrome(key: .init(isWide: false, scale: 2, isTurned: false))
        .background(.gray)
}

#Preview("Phone chrome — 4:3, ×2, landscape") {
    HallPhoneChrome(key: .init(isWide: false, scale: 2, isTurned: true))
        .background(.gray)
}
