//
//  TicketTear.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import SwiftUI
import MetalKit
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct TicketTear<Content: View>: View {

    private let config: TicketTearConfig
    private let content: Content
    private let onComplete: (() -> Void)?
    private let resetToken: Int
    private let contentID: AnyHashable
    private let probe: TearFrameRateProbe?
    private let isGrabEnabled: Bool
    private let rasterizesContent: Bool
    private let returnToken: Int
    private let onReturnChange: ((Bool) -> Void)?
    private let onStubAwayChange: ((Bool) -> Void)?

    @MainActor
    private struct EngineBox {
        let engine = TicketTearEngine()
    }

    @State private var box = EngineBox()
    @State private var size: CGSize = .zero
    @State private var texture: MTLTexture?
    @State private var accepted = false
    @State private var refused = false
    @State private var canResumeTear = false
    @State private var phase = TearPhase.rest
    @State private var completionToken = 0
    @GestureState private var isGrabbing = false

    @Environment(\.displayScale) private var displayScale

    private var pixelGrid: PixelGrid { PixelGrid(displayScale: displayScale) }

    init(config: TicketTearConfig = TicketTearConfig(),
         resetToken: Int = 0,
         contentID: AnyHashable = 0,
         isGrabEnabled: Bool = true,
         rasterizesContent: Bool = false,
         returnToken: Int = 0,
         onComplete: (() -> Void)? = nil,
         onReturnChange: ((Bool) -> Void)? = nil,
         onStubAwayChange: ((Bool) -> Void)? = nil,
         probe: TearFrameRateProbe? = nil,
         @ViewBuilder content: () -> Content) {
        self.config = config
        self.content = content()
        self.onComplete = onComplete
        self.resetToken = resetToken
        self.contentID = contentID
        self.isGrabEnabled = isGrabEnabled
        self.rasterizesContent = rasterizesContent
        self.returnToken = returnToken
        self.onReturnChange = onReturnChange
        self.onStubAwayChange = onStubAwayChange
        self.probe = probe
    }

    private var engine: TicketTearEngine { box.engine }

    var body: some View {
        content
            .environment(\.ticketStubIsAway, phase.hidesLiveStub)
            .modifier(Rasterize(isActive: phase.flattensContent(rasterizing: rasterizesContent)))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                guard newSize != size else { return }
                size = newSize
                engine.updateSize(newSize)
                snapshotTexture()
            }
            .mask(alignment: .topLeading) {
                StubCutout(fullSize: size, stubRect: phase.cutsOutStub ? stubRect : .zero)
                    .fill(style: FillStyle(eoFill: true))
            }
            .padding(config.canvasPadding)
            .overlay {
                if config.showsMesh {
                    TicketCurlRenderer(engine: engine, config: config, ticketSize: size,
                                       texture: texture, canvasPadding: config.canvasPadding,
                                       probe: probe,
                                       onDrawn: {
                                           if phase == .arming { phase = .tearing }
                                           if phase == .returning { phase = .healing }
                                       },
                                       onPark: { phase = phase == .detached ? .gone : .rest })
                        .opacity(phase.showsShader ? 1 : 0)
                }
            }
            .overlay { grabArea }
            .padding(-config.canvasPadding)
            .overlay(alignment: .top) { frameRateReadout }
            .onChange(of: phase.cutsOutStub) { _, away in
                onStubAwayChange?(away)
            }
            .onChange(of: resetToken) { _, _ in
                engine.reset()
                if phase == .detached || phase.hidesLiveStub {
                    phase = .tearing
                    onReturnChange?(false)
                }
            }
            .onChange(of: returnToken) { _, _ in
                if engine.returnStub(force: true) {
                    phase = .returning
                    onReturnChange?(true)
                } else {
                    onReturnChange?(false)
                    onStubAwayChange?(false)
                }
            }
            .onChange(of: isGrabEnabled) { _, enabled in
                if !enabled { engine.cancelTear() }
            }
            .onChange(of: isGrabbing) { _, grabbing in
                if !grabbing { releaseTear() }
            }
            .onChange(of: contentID) { _, _ in
                snapshotTexture()
            }
            .onChange(of: completionToken) { _, _ in
                let finished = onComplete
                Task { @MainActor in finished?() }
            }
            .onAppear {
                engine.onResumableChange = { canResumeTear = $0 }
                engine.onTabBreak = { Haptics.shared.tabBroke() }
                engine.onTabHeal = { Haptics.shared.tabHealed() }
                engine.onReturnComplete = { onReturnChange?(false) }
                engine.onComplete = {
                    Haptics.shared.completed()
                    phase = .detached
                }
                engine.onDetachPush = {
                    completionToken &+= 1
                }
                snapshotTexture()
            }
    }

    // MARK: Layout

    private var stubRect: CGRect {
        let slack: CGFloat = 1
        switch config.stubSide {
        case .trailing:
            let seam = pixelGrid.snapped(size.width - config.stubExtent)
            return CGRect(x: seam, y: -slack,
                          width: size.width + slack - seam, height: size.height + slack * 2)
        case .leading:
            let seam = pixelGrid.snapped(config.stubExtent)
            return CGRect(x: -slack, y: -slack,
                          width: seam + slack, height: size.height + slack * 2)
        case .bottom:
            let seam = pixelGrid.snapped(size.height - config.stubExtent)
            return CGRect(x: -slack, y: seam,
                          width: size.width + slack * 2, height: size.height + slack - seam)
        case .top:
            let seam = pixelGrid.snapped(config.stubExtent)
            return CGRect(x: -slack, y: -slack,
                          width: size.width + slack * 2, height: seam + slack)
        }
    }

    private var grabArea: some View {
        grabShape
            .fill(config.showsGrabZone ? Color.red.opacity(0.28) : Color.clear)
            .contentShape(grabShape)
            .gesture(drag)
            .allowsHitTesting((isGrabEnabled && phase != .healing) || accepted)
    }

    private var grabShape: Path {
        guard size != .zero else { return Path() }
        let pad = config.canvasPadding
        var path = Path()
        for rect in canResumeTear ? [stubRect] : cornerGrabRects {
            path.addRect(rect.offsetBy(dx: pad, dy: pad))
        }
        return path
    }

    private var cornerGrabRects: [CGRect] {
        let d = config.grabDepth
        switch config.stubSide {
        case .bottom:
            let y = size.height - d
            return [CGRect(x: 0, y: y, width: d, height: d),
                    CGRect(x: size.width - d, y: y, width: d, height: d)]
        case .top:
            return [CGRect(x: 0, y: 0, width: d, height: d),
                    CGRect(x: size.width - d, y: 0, width: d, height: d)]
        case .trailing:
            let x = size.width - d
            return [CGRect(x: x, y: 0, width: d, height: d),
                    CGRect(x: x, y: size.height - d, width: d, height: d)]
        case .leading:
            return [CGRect(x: 0, y: 0, width: d, height: d),
                    CGRect(x: 0, y: size.height - d, width: d, height: d)]
        }
    }

    // MARK: Snapshot

    private func snapshotTexture() {
        guard size.width > 1, size.height > 1 else { return }
        texture = TicketSnapshot.texture(of: content, scale: displayScale)
    }

    // MARK: Overlay

    @ViewBuilder
    private var frameRateReadout: some View {
        if config.showsFrameRate, let probe {
            TearFrameRateBadge(probe: probe)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .offset(y: -26)
                .allowsHitTesting(false)
        }
    }

    // MARK: Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isGrabbing) { _, state, _ in state = true }
            .onChanged { value in
                if !accepted {
                    guard !refused else { return }
                    guard engine.begin(at: ticketSpace(value.startLocation)) else {
                        refused = true
                        return
                    }
                    accepted = true
                    if phase == .rest { phase = .arming }
                    Haptics.shared.prepare()
                }
                engine.move(to: ticketSpace(value.location))
            }
    }

    private func releaseTear() {
        if accepted { engine.end() }
        accepted = false
        refused = false
    }

    private func ticketSpace(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - config.canvasPadding, y: p.y - config.canvasPadding)
    }
}

private func previewConfig(showsGrabZone: Bool) -> TicketTearConfig {
    var config = TicketTearConfig()
    config.stubSide = .bottom
    config.stubExtent = 120
    config.pitch = 26
    config.perfEndInset = TicketStyle.tearNotchRadius
    config.showsGrabZone = showsGrabZone
    return config
}

private var previewTicket: some View {
    VStack(spacing: 0) {
        Color.white
            .frame(width: 280, height: 300)
            .mask(TicketPerforationShape(scallopedEdges: .top, tearNotchEdges: .bottom))
        Color.white
            .frame(width: 280, height: 120)
            .mask(TicketPerforationShape(scallopedEdges: .bottom, tearNotchEdges: .top))
    }
}

#Preview("Отрыв корешка") {
    TicketTear(config: previewConfig(showsGrabZone: false)) { previewTicket }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
}

#Preview("Зоны захвата") {
    TicketTear(config: previewConfig(showsGrabZone: true)) { previewTicket }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
}
