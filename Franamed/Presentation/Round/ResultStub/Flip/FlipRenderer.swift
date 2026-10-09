//
//  FlipRenderer.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import SwiftUI
import MetalKit
import simd

struct FlipUniforms {
    var projection: simd_float4x4
    var lightDir: SIMD4<Float>
    var hallTint: SIMD4<Float>
    var hallShape: SIMD4<Float>

    var width: Float
    var height: Float
    var angle: Float
    var bend: Float

    var perspective: Float
    var sheen: Float
    var cols: Float
    var rows: Float

    var viewWidth: Float
    var viewHeight: Float
    var thickness: Float
    var gap: Float

    var face: Float
    var faceOffset: Float
    var edgeCount: Float
    var gloss: Float

    var tearLine: SIMD4<Float>
    var tearShape: SIMD4<Float>
    var tearState: SIMD4<Float>
    var tearHeal: SIMD4<Float>
}

enum FlipMesh {
    static let columns = 48
    static let rows = 12

    static let indexCount = columns * rows * 6

    static func makeIndices() -> [UInt16] {
        var indices: [UInt16] = []
        indices.reserveCapacity(columns * rows * 6)
        let stride = columns + 1
        for row in 0..<rows {
            for col in 0..<columns {
                let topLeft = UInt16(row * stride + col)
                let topRight = topLeft + 1
                let bottomLeft = UInt16((row + 1) * stride + col)
                let bottomRight = bottomLeft + 1
                indices += [topLeft, bottomLeft, topRight, topRight, bottomLeft, bottomRight]
            }
        }
        return indices
    }
}

struct FlipLighting: Equatable {
    var tint: SIMD3<Float>
    var amount: Float
    var exposure: Float
    var sheenScale: Float = 1

    static let neutral = FlipLighting(tint: .one, amount: 0, exposure: 1)
}

extension EnvironmentValues {
    @Entry var flipTilt: Double = 0
    @Entry var flipLighting = FlipLighting.neutral
    @Entry var flipRecordingLighting: FlipLighting?
    @Entry var flipTear = FlipTear.none
}

struct FlipRenderer: UIViewRepresentable {
    static let sampleCount = 4

    let engine: FlipEngine
    let frontTexture: MTLTexture?
    let backTexture: MTLTexture?
    let stubSize: CGSize
    let edgeStyle: TicketEdgeStyle
    let lighting: FlipLighting
    let tilt: Double
    let isProtected: Bool
    var tear = FlipTear.none
    let providesSnapshot: Bool

    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    func makeUIView(context: Context) -> ProtectedBox {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.isOpaque = false
        view.backgroundColor = .clear
        (view.layer as? CAMetalLayer)?.isOpaque = false
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = Self.sampleCount
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isUserInteractionEnabled = false
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = context.coordinator
        let hideOthers = engine.onCanvasHidden
        engine.onCanvasHidden = { [weak view] isHidden in
            hideOthers?(isHidden)
            view?.isHidden = isHidden
        }
        let wakeOthers = engine.onWake
        engine.onWake = { [weak view] in
            wakeOthers?()
            view?.isPaused = false
        }
        context.coordinator.view = view
        if let device = view.device {
            context.coordinator.configure(device: device,
                                          colorFormat: view.colorPixelFormat,
                                          depthFormat: view.depthStencilPixelFormat)
        }
        return ProtectedBox(child: view)
    }

    func updateUIView(_ box: ProtectedBox, context: Context) {
        box.isProtected = isProtected
        if providesSnapshot {
            engine.litSnapshot = { [weak coordinator = context.coordinator] in coordinator?.snapshot() }
            engine.tearSnapshot = { [weak coordinator = context.coordinator] in coordinator?.tearSnapshot() }
            engine.isTearHealing = { [weak coordinator = context.coordinator] in coordinator?.isTearHealing ?? false }
        }
        let coordinator = context.coordinator
        let needsFrame = coordinator.frontTexture !== frontTexture
            || coordinator.backTexture !== backTexture
            || coordinator.stubSize != stubSize
        coordinator.frontTexture = frontTexture
        coordinator.backTexture = backTexture
        coordinator.stubSize = stubSize
        coordinator.setOutline(size: stubSize, edgeStyle: edgeStyle)
        let lightChanged = coordinator.lighting != lighting || coordinator.tilt != tilt
        coordinator.lighting = lighting
        coordinator.tilt = tilt
        let tearChanged = coordinator.setTear(tear)
        if needsFrame || coordinator.outlineChanged || lightChanged || tearChanged {
            coordinator.view?.isPaused = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        let engine: FlipEngine
        var frontTexture: MTLTexture?
        var backTexture: MTLTexture?
        var stubSize: CGSize = .zero
        var lighting = FlipLighting.neutral
        var tilt: Double = 0
        weak var view: MTKView?
        private(set) var outlineChanged = false

        init(engine: FlipEngine) {
            self.engine = engine
        }

        private var commandQueue: MTLCommandQueue!
        private var pipeline: MTLRenderPipelineState!
        private var edgePipeline: MTLRenderPipelineState!
        private var tearPipeline: MTLRenderPipelineState?
        private var indexBuffer: MTLBuffer!
        private var sampler: MTLSamplerState!
        private var depthState: MTLDepthStencilState!

        private var device: MTLDevice!
        private var outline = FlipEdge.Outline()
        private var outlineBuffer: MTLBuffer?
        private var outlineSize: CGSize = .zero
        private var outlineStyle: TicketEdgeStyle = .scalloped

        private static let tearSegments = 160
        private var tear = FlipTearMotion()

        var isTearHealing: Bool { tear.isHealing }

        func setTear(_ tear: FlipTear) -> Bool { self.tear.setTarget(tear) }

        func setOutline(size: CGSize, edgeStyle: TicketEdgeStyle) {
            outlineChanged = size.width > 1 && (size != outlineSize || edgeStyle != outlineStyle)
            guard outlineChanged else { return }
            outlineSize = size
            outlineStyle = edgeStyle
            outline = FlipEdge.outline(size: size, edgeStyle: edgeStyle)
            outlineBuffer = outline.vertices.isEmpty ? nil : device?.makeBuffer(
                bytes: outline.vertices,
                length: outline.vertices.count * MemoryLayout<FlipEdge.Vertex>.stride,
                options: .storageModeShared)
        }

        func configure(device: MTLDevice, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) {
            self.device = device
            commandQueue = device.makeCommandQueue()

            let indices = FlipMesh.makeIndices()
            indexBuffer = device.makeBuffer(bytes: indices,
                                            length: indices.count * MemoryLayout<UInt16>.stride,
                                            options: .storageModeShared)

            guard let library = device.makeDefaultLibrary(),
                  let vertexFunction = library.makeFunction(name: "ticketFlipVertex"),
                  let edgeFunction = library.makeFunction(name: "ticketFlipEdgeVertex"),
                  let tearFunction = library.makeFunction(name: "ticketFlipTearVertex"),
                  let fragmentFunction = library.makeFunction(name: "ticketFlipFragment") else {
                print("[TicketFlip] shader library unavailable")
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.depthAttachmentPixelFormat = depthFormat
            descriptor.colorAttachments[0].pixelFormat = colorFormat

            descriptor.rasterSampleCount = FlipRenderer.sampleCount
            descriptor.isAlphaToCoverageEnabled = true

            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

            descriptor.vertexFunction = edgeFunction
            edgePipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

            descriptor.vertexFunction = tearFunction
            tearPipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.depthCompareFunction = .less
            depthDescriptor.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: depthDescriptor)

            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated { render(in: view) }
        }

        private func render(in view: MTKView) {
            let now = CACurrentMediaTime()
            engine.step(now: now)
            let isTearMoving = tear.step(now: now)
            let parking = frontTexture != nil && !engine.isAnimating && !isTearMoving
            view.isPaused = parking
            if parking { engine.park() }

            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  encode(into: commandBuffer, descriptor: descriptor, size: view.bounds.size)
            else { return }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        static let tearMargin: CGFloat = 10

        func tearSnapshot() -> (plain: UIImage, lit: UIImage?)? {
            guard tear.showsMarks else { return nil }
            let lit = snapshot(margin: Self.tearMargin)
            let saved = (lighting, tilt)
            lighting = .neutral
            tilt = 0
            defer { (lighting, tilt) = saved }
            return snapshot(margin: Self.tearMargin).map { ($0, lit) }
        }

        func snapshot(margin: CGFloat = 0) -> UIImage? {
            guard let view, let device, view.drawableSize.width > 0 else { return nil }
            let width = Int(view.drawableSize.width)
            let height = Int(view.drawableSize.height)
            func texture(_ format: MTLPixelFormat, samples: Int, storage: MTLStorageMode) -> MTLTexture? {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width,
                                                                          height: height, mipmapped: false)
                descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
                descriptor.sampleCount = samples
                descriptor.usage = .renderTarget
                descriptor.storageMode = storage
                return device.makeTexture(descriptor: descriptor)
            }
            guard let color = texture(view.colorPixelFormat, samples: FlipRenderer.sampleCount, storage: .private),
                  let resolve = texture(view.colorPixelFormat, samples: 1, storage: .shared),
                  let depth = texture(view.depthStencilPixelFormat, samples: FlipRenderer.sampleCount, storage: .private),
                  let commandBuffer = commandQueue.makeCommandBuffer()
            else { return nil }

            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = color
            descriptor.colorAttachments[0].resolveTexture = resolve
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            descriptor.colorAttachments[0].storeAction = .multisampleResolve
            descriptor.depthAttachment.texture = depth
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.clearDepth = 1
            descriptor.depthAttachment.storeAction = .dontCare
            guard encode(into: commandBuffer, descriptor: descriptor, size: view.bounds.size) else { return nil }
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            resolve.getBytes(&bytes, bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: info),
                  let image = context.makeImage()
            else { return nil }
            let scale = view.drawableSize.width / max(view.bounds.width, 1)
            let inset = (FlipLook.canvasPadding - margin) * scale
            let crop = CGRect(x: inset, y: inset, width: (stubSize.width + margin * 2) * scale,
                              height: (stubSize.height + margin * 2) * scale)
            return image.cropping(to: crop.integral).map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
        }

        private func encode(into commandBuffer: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor,
                            size: CGSize) -> Bool {
            guard let pipeline, let frontTexture,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            else { return false }

            encoder.setDepthStencilState(depthState)
            encoder.setFragmentTexture(frontTexture, index: 0)
            encoder.setFragmentTexture(backTexture ?? frontTexture, index: 1)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.setCullMode(.none)

            for half in tear.halves {
                encoder.setRenderPipelineState(pipeline)
                for (face, offset) in [(Float(1), Float(1)), (Float(2), Float(-1))] {
                    var uniforms = self.uniforms(viewSize: size, face: face, faceOffset: offset, half: half)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<FlipUniforms>.stride, index: 1)
                    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FlipUniforms>.stride, index: 1)
                    encoder.drawIndexedPrimitives(type: .triangle,
                                                  indexCount: FlipMesh.indexCount,
                                                  indexType: .uint16,
                                                  indexBuffer: indexBuffer,
                                                  indexBufferOffset: 0)
                }

                if let edgePipeline, let outlineBuffer {
                    encoder.setRenderPipelineState(edgePipeline)
                    encoder.setVertexBuffer(outlineBuffer, offset: 0, index: 0)
                    for range in outline.ranges {
                        var uniforms = self.uniforms(viewSize: size, face: 0, faceOffset: 0,
                                                     edgeCount: Float(range.count), half: half)
                        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FlipUniforms>.stride, index: 1)
                        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FlipUniforms>.stride, index: 1)
                        encoder.setVertexBufferOffset(
                            range.lowerBound * MemoryLayout<FlipEdge.Vertex>.stride, index: 0)
                        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0,
                                               vertexCount: (range.count + 1) * 2)
                    }
                }

                if half != 0, let tearPipeline {
                    encoder.setRenderPipelineState(tearPipeline)
                    var uniforms = self.uniforms(viewSize: size, face: 0, faceOffset: 0,
                                                 edgeCount: Float(Self.tearSegments), half: half)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<FlipUniforms>.stride, index: 1)
                    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FlipUniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0,
                                           vertexCount: (Self.tearSegments + 1) * 2)
                }
            }
            encoder.endEncoding()
            return true
        }

        private func uniforms(viewSize: CGSize, face: Float, faceOffset: Float,
                              edgeCount: Float = 0, half: Float = 0) -> FlipUniforms {
            let tear = self.tear.uniforms(width: stubSize.width, half: half)
            return FlipUniforms(
                projection: Self.ortho(width: Float(viewSize.width), height: Float(viewSize.height)),
                lightDir: SIMD4(-0.42, -0.62, 0.86, 0),
                hallTint: SIMD4(lighting.tint, lighting.amount),
                hallShape: SIMD4(Float(tilt * .pi / 180), lighting.exposure, 0, lighting.sheenScale),
                width: Float(stubSize.width),
                height: Float(stubSize.height),
                angle: Float(engine.angle),
                bend: Float(engine.bend),
                perspective: FlipLook.perspective,
                sheen: FlipLook.sheen,
                cols: Float(FlipMesh.columns),
                rows: Float(FlipMesh.rows),
                viewWidth: Float(viewSize.width),
                viewHeight: Float(viewSize.height),
                thickness: Float(TicketStyle.paperThickness),
                gap: Float(max(TicketStyle.paperThickness, 0.25) * 0.5),
                face: face,
                faceOffset: faceOffset,
                edgeCount: edgeCount,
                gloss: FlipLook.gloss,
                tearLine: tear.line,
                tearShape: tear.shape,
                tearState: tear.state,
                tearHeal: tear.heal
            )
        }

        private static func ortho(width: Float, height: Float) -> simd_float4x4 {
            guard width > 0, height > 0 else { return matrix_identity_float4x4 }
            return simd_float4x4(
                SIMD4(2 / width, 0, 0, 0),
                SIMD4(0, -2 / height, 0, 0),
                SIMD4(0, 0, 1, 0),
                SIMD4(-1, 1, 0, 1)
            )
        }
    }
}
