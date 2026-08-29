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
    var probe: TearFrameRateProbe?
    var onDrawn: (() -> Void)?
    var onPark: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        let opaque = config.opaqueLayerProbe
        view.isOpaque = opaque
        view.backgroundColor = opaque ? .black : .clear
        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.isOpaque = opaque
        }
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        let samples = config.multisampling && view.device?.supportsTextureSampleCount(4) == true ? 4 : 1
        view.sampleCount = samples
        view.clearColor = MTLClearColorMake(0, 0, 0, opaque ? 1 : 0)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.isUserInteractionEnabled = false
        view.delegate = context.coordinator
        context.coordinator.configure(device: view.device!, colorFormat: view.colorPixelFormat,
                                       depthFormat: view.depthStencilPixelFormat,
                                       sampleCount: samples)
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
        var probe: TearFrameRateProbe?
        var onDrawn: (() -> Void)?
        var onPark: (() -> Void)?

        private var commandQueue: MTLCommandQueue!
        private var pipeline: MTLRenderPipelineState!
        private var depthState: MTLDepthStencilState!
        private var indexBuffer: MTLBuffer!
        private var sampler: MTLSamplerState!

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

            let indices = TicketCurlTopology.makeIndices()
            indexBuffer = device.makeBuffer(bytes: indices,
                                            length: indices.count * MemoryLayout<UInt16>.stride,
                                            options: .storageModeShared)

            let library = device.makeDefaultLibrary()!
            let pdesc = MTLRenderPipelineDescriptor()
            pdesc.vertexFunction = library.makeFunction(name: "ticketCurlVertex")!
            pdesc.fragmentFunction = library.makeFunction(name: "ticketCurlFragment")!
            pdesc.depthAttachmentPixelFormat = depthFormat
            pdesc.rasterSampleCount = sampleCount

            let color = pdesc.colorAttachments[0]!
            color.pixelFormat = colorFormat
            color.isBlendingEnabled = true
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha

            do {
                pipeline = try device.makeRenderPipelineState(descriptor: pdesc)
            } catch {
                print("[TicketCurl] pipeline state creation failed: \(error)")
            }

            let ddesc = MTLDepthStencilDescriptor()
            ddesc.depthCompareFunction = .less
            ddesc.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: ddesc)

            let sdesc = MTLSamplerDescriptor()
            sdesc.minFilter = .linear
            sdesc.magFilter = .linear
            sdesc.sAddressMode = .clampToEdge
            sdesc.tAddressMode = .clampToEdge
            sampler = device.makeSamplerState(descriptor: sdesc)
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

            guard let cmd = commandQueue.makeCommandBuffer(),
                  let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

            var uniforms = self.uniforms(for: pose, viewSize: view.bounds.size)
            enc.setRenderPipelineState(pipeline)
            enc.setDepthStencilState(depthState)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<CurlUniforms>.stride, index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<CurlUniforms>.stride, index: 1)
            enc.setFragmentTexture(tex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.setCullMode(.none)
            enc.drawIndexedPrimitives(type: .triangle,
                                      indexCount: TicketCurlTopology.indexCount,
                                      indexType: .uint16,
                                      indexBuffer: indexBuffer,
                                      indexBufferOffset: 0)
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

        private func uniforms(for pose: TearPose, viewSize: CGSize) -> CurlUniforms {
            CurlUniforms(
                projection: Self.orthoProjection(width: Float(viewSize.width),
                                                  height: Float(viewSize.height)),
                lightDir: SIMD4(-0.42, -0.62, 0.86, 0),

                perfOriginX: Float(pose.perfOrigin.x),
                perfOriginY: Float(pose.perfOrigin.y),
                perfDirX: Float(pose.perfDir.dx),
                perfDirY: Float(pose.perfDir.dy),

                stubNX: Float(pose.stubN.dx),
                stubNY: Float(pose.stubN.dy),
                offsetX: Float(pose.offset.dx),
                offsetY: Float(pose.offset.dy),

                ticketWidth: Float(ticketSize.width),
                ticketHeight: Float(ticketSize.height),
                apexA: Float(pose.apexA),
                theta: Float(pose.theta),

                perfLength: Float(pose.perfLength),
                stubExtent: Float(config.stubExtent),
                canvasPadding: Float(canvasPadding),
                colsA: Float(TicketCurlTopology.colsA),

                colsB: Float(TicketCurlTopology.colsB),
                opacity: Float(pose.opacity),

                front: Float(pose.front),
                pitch: Float(pose.pitch),
                holeLen: Float(pose.holeLen),
                holeHalfWidth: Float(config.holeHalfWidth),

                jitterAmp: Float(config.tearJitter),
                strainCell: Float(pose.strainCell),
                strain: Float(pose.strain),
                neckFraction: Float(config.neckFraction),

                sheen: Float(config.sheen),
                patternOrigin: Float(pose.patternOrigin),
                patternSign: Float(pose.patternSign),
                patternInset: Float(pose.patternInset),

                crackWidth: Float(config.crackWidth),
                tornSoftness: Float(config.tornSoftness),
                slotCorner: Float(config.slotCorner),
                tornGap: Float(config.tornGap),

                paperBack: Self.rgba(config.backColor))
        }

        private static func orthoProjection(width: Float, height: Float) -> simd_float4x4 {
            guard width > 0, height > 0 else { return matrix_identity_float4x4 }
            return simd_float4x4(
                SIMD4(2 / width, 0, 0, 0),
                SIMD4(0, -2 / height, 0, 0),
                SIMD4(0, 0, 1, 0),
                SIMD4(-1, 1, 0, 1)
            )
        }

        private static func rgba(_ color: Color) -> SIMD4<Float> {
            #if canImport(UIKit)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return SIMD4(Float(r), Float(g), Float(b), Float(a))
            #else
            return SIMD4(0.96, 0.95, 0.93, 1)
            #endif
        }
    }
}
