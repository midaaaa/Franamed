//
//  SharePanel.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 13.10.2026.
//

import SwiftUI

struct SharePanel: View {
    let material: ShareMaterial
    @Binding var mode: ShareMode
    @Binding var background: ShareBackground
    @Binding var format: ShareFormat
    let onShare: () -> Void

    private static let swatchSize: CGFloat = 36
    private static let swatchSlot = swatchSize + 8 + 20
    private static let swatchFade: CGFloat = 20
    private static let swatchFocus = CGPoint(x: ShareFormat.baseWidth / 2, y: ShareMaterial.cardFrame.maxY - 12)
    private static let swatchSpan: CGFloat = 200
    private static let swatchRowHeight = swatchSize + 8 + swatchFade

    static func height(for material: ShareMaterial, format: ShareFormat, width: CGFloat) -> CGFloat {
        let panel = SharePanel(material: material, mode: .constant(.answer), background: .constant(.hall),
                               format: .constant(format), onShare: {})
        let host = UIHostingController(rootView: panel.environment(\.colorScheme, .dark))
        return ceil(host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    var body: some View {
        VStack(spacing: 0) {
            swatches
                .padding(.bottom, Self.swatchFade)
                .modifier(SwatchReveal(progress: format == .sticker ? 0 : 1, height: Self.swatchRowHeight,
                                       fade: Self.swatchFade))

            formats
                .padding(.bottom, 16)

            Toggle(isOn: hidesTitle) {
                Text("Ответ")
                    .strikethrough(mode.hidesAnswer)
                    .foregroundStyle(mode.hidesAnswer ? .black : .white)
            }
            .toggleStyle(.button)
            .tint(.white)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

            Button(action: onShare) {
                Text("Поделиться")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .animation(.snappy, value: format)
        .animation(.snappy, value: mode)
    }

    private var formats: some View {
        HStack(spacing: 28) {
            ForEach(ShareFormat.allCases) { option in
                Button {
                    format = option
                } label: {
                    ShareFormatGlyph(format: option, isSelected: format == option)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(ShareBackground.allCases) { option in
                let isAvailable = option.isAvailable(in: mode, material: material)
                Button {
                    background = option
                } label: {
                    swatch(option)
                        .frame(width: Self.swatchSize, height: Self.swatchSize)
                        .clipShape(.circle)
                        .overlay { Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1) }
                        .padding(4)
                        .overlay {
                            if background.shown(in: mode, material: material) == option {
                                Circle().strokeBorder(.white, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .contentShape(.circle)
                .geometryGroup()
                .scaleEffect(isAvailable ? 1 : 0.001)
                .opacity(isAvailable ? 1 : 0)
                .frame(width: isAvailable ? Self.swatchSlot : 0)
                .allowsHitTesting(isAvailable)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var hidesTitle: Binding<Bool> {
        Binding { mode.hidesAnswer } set: { mode = $0 ? .riddle : .answer }
    }

    private func swatch(_ option: ShareBackground) -> some View {
        let scale = Self.swatchSize / Self.swatchSpan
        return ShareCard(material: material, mode: mode, background: option, format: .story,
                         showsStub: false, showsOverlays: false)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: Self.swatchSize / 2 - Self.swatchFocus.x * scale,
                    y: Self.swatchSize / 2 - Self.swatchFocus.y * scale)
            .frame(width: Self.swatchSize, height: Self.swatchSize, alignment: .topLeading)
    }
}

private struct SwatchReveal: ViewModifier, Animatable {
    var progress: CGFloat
    let height: CGFloat
    let fade: CGFloat

    private static let fadeCurve: [(location: CGFloat, opacity: Double)] = [
        (0, 1), (0.25, 0.85), (0.5, 0.5), (0.75, 0.15), (1, 0),
    ]

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let shown = height * progress
        content
            .opacity(Double(progress * progress))
            .frame(height: shown, alignment: .top)
            .mask {
                LinearGradient(stops: stops(for: shown), startPoint: .top, endPoint: .bottom)
            }
            .clipped()
    }

    private func stops(for shown: CGFloat) -> [Gradient.Stop] {
        guard shown > 0 else { return [.init(color: .clear, location: 0)] }
        let start = max(shown - fade, 0) / shown
        return [.init(color: .black, location: 0)] + Self.fadeCurve.map {
            .init(color: .black.opacity($0.opacity), location: start + (1 - start) * $0.location)
        }
    }
}

private struct ShareFormatGlyph: View {
    let format: ShareFormat
    let isSelected: Bool

    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false

    private static let stubDrawingWidth: CGFloat = 110
    private static let stubWidth: CGFloat = 34

    var body: some View {
        ZStack {
            shape
                .fill(.white)
                .animation(.easeOut(duration: 0.15)) { $0.opacity(isSelected ? 1 : 0) }
            shape
                .stroke(.white.opacity(isSelected ? 1 : 0.55), lineWidth: lineWidth)
        }
        .frame(width: drawingSize.width, height: drawingSize.height)
        .scaleEffect(scale)
        .frame(width: drawingSize.width * scale, height: drawingSize.height * scale)
        .geometryGroup()
    }

    private var drawingSize: CGSize {
        switch format {
        case .story: CGSize(width: 18, height: 32)
        case .square: CGSize(width: 28, height: 28)
        case .sticker:
            CGSize(width: Self.stubDrawingWidth, height: Self.stubDrawingWidth * ShareStubPlacement.stubAspect)
        }
    }

    private var scale: CGFloat {
        format == .sticker ? Self.stubWidth / Self.stubDrawingWidth : 1
    }

    private var lineWidth: CGFloat { 1.5 / scale }

    private var shape: AnyShape {
        switch format {
        case .story, .square: AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .sticker: AnyShape(ResultStubShape(edgeStyle: TicketEdgeStyle(hasScallops: hasScallops)))
        }
    }
}
