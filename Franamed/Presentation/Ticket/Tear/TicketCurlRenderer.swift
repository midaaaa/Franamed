//
//  TicketCurlRenderer.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import SwiftUI
import MetalKit

struct TicketCurlRenderer: UIViewRepresentable {
    let engine: TicketTearEngine
    var config: TicketTearConfig
    var ticketSize: CGSize
    var texture: MTLTexture?
    var canvasPadding: CGFloat
    var stubShape: (any Shape & Hashable)?
    var probe: TearFrameRateProbe?
    var onDrawn: (() -> Void)?
    var onPark: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        let device = MTLCreateSystemDefaultDevice()
        view.device = device
        let opaque = config.opaqueLayerProbe
        view.isOpaque = opaque
        view.backgroundColor = opaque ? .black : .clear
        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.isOpaque = opaque
        }
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        let samples = config.multisampling && device?.supportsTextureSampleCount(4) == true ? 4 : 1
        view.sampleCount = samples
        view.clearColor = MTLClearColorMake(0, 0, 0, opaque ? 1 : 0)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.isUserInteractionEnabled = false
        view.delegate = context.coordinator
        if let device {
            context.coordinator.configure(device: device, colorFormat: view.colorPixelFormat,
                                          depthFormat: view.depthStencilPixelFormat,
                                          sampleCount: samples)
        }
        context.coordinator.attach(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        let c = context.coordinator
        let needsFrame = c.texture !== texture
            || c.ticketSize != ticketSize
            || c.canvasPadding != canvasPadding
            || c.config != config

        c.engine.config = config
        c.config = config
        c.ticketSize = ticketSize
        c.canvasPadding = canvasPadding
        c.texture = texture
        c.stubShape = stubShape
        c.probe = probe
        c.onDrawn = onDrawn
        c.onPark = onPark

        if needsFrame { uiView.isPaused = false }
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        let engine: TicketTearEngine
        var config = TicketTearConfig()
        var ticketSize: CGSize = .zero
        var canvasPadding: CGFloat = 0
        var texture: MTLTexture?
        var stubShape: (any Shape & Hashable)?
        var probe: TearFrameRateProbe?
        var onDrawn: (() -> Void)?
        var onPark: (() -> Void)?

        private var commandQueue: MTLCommandQueue?
        private var pipeline: TicketCurlPipeline?

        private var drawnFrames = 0
        private var didNotifyDrawn = false
        private var lastDrawTime: CFTimeInterval = 0
        private var frameDuration: Double = 0
        private var cpuStart: CFTimeInterval = 0

        private weak var view: MTKView?

        init(engine: TicketTearEngine) {
            self.engine = engine
        }

        func attach(view: MTKView) {
            self.view = view
            engine.onWake = { [weak view] in view?.isPaused = false }
        }

        // MARK: Pipeline

        func configure(device: MTLDevice, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat,
                       sampleCount: Int) {
            commandQueue = device.makeCommandQueue()
            guard let library = device.makeDefaultLibrary() else {
                print("[TicketCurl] shader library unavailable")
                return
            }
            pipeline = TicketCurlPipeline(device: device, library: library, colorFormat: colorFormat,
                                          depthFormat: depthFormat, sampleCount: sampleCount)
        }

        // MARK: Frame

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated { self.render(in: view) }
        }

        private func render(in view: MTKView) {
            trackFrameRate()
            cpuStart = CACurrentMediaTime()

            engine.config = config
            engine.step(now: Date())
            let pose = engine.currentPose()

            let parking = texture != nil && !engine.isAnimating
            view.isPaused = parking
            defer {
                if parking {
                    lastDrawTime = 0
                    probe?.park()
                    if drawnFrames > 0 {
                        notifyDrawn()
                        drawnFrames = 0
                        didNotifyDrawn = false
                        onPark?()
                    }
                }
            }

            guard let tex = texture, let pipeline else { return }

            let waitStart = CACurrentMediaTime()
            guard let drawable = view.currentDrawable,
                  let rpd = view.currentRenderPassDescriptor else { return }
            let waited = CACurrentMediaTime() - waitStart

            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            rpd.depthAttachment.loadAction = .clear
            rpd.depthAttachment.clearDepth = 1.0

            guard let cmd = commandQueue?.makeCommandBuffer(),
                  let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

            pipeline.setOutline(shape: stubShape, config: config, ticketSize: ticketSize)
            let uniforms = TicketCurlPipeline.uniforms(for: pose, config: config, ticketSize: ticketSize,
                                                       canvasPadding: canvasPadding,
                                                       viewSize: view.bounds.size)
            pipeline.encode(into: enc, uniforms: uniforms, pose: pose, texture: tex)
            enc.endEncoding()
            cmd.present(drawable)

            if let probe {
                cmd.addCompletedHandler { buffer in
                    let elapsed = buffer.gpuEndTime - buffer.gpuStartTime
                    guard elapsed > 0 else { return }
                    Task { @MainActor in probe.record(gpu: elapsed) }
                }
            }

            cmd.commit()

            drawnFrames += 1
            if drawnFrames >= 2 { notifyDrawn() }

            let done = CACurrentMediaTime()
            if frameDuration > 0, !parking {
                probe?.record(frameDuration: frameDuration, cpu: done - cpuStart,
                              wait: waited, at: done)
            }
        }

        private func notifyDrawn() {
            guard !didNotifyDrawn else { return }
            didNotifyDrawn = true
            onDrawn?()
        }

        private func trackFrameRate() {
            let now = CACurrentMediaTime()
            defer { lastDrawTime = now }
            guard lastDrawTime > 0 else { return }
            let dt = now - lastDrawTime
            guard dt > 0, dt < 0.5 else {
                frameDuration = 0
                return
            }
            frameDuration = dt
        }
    }
}
