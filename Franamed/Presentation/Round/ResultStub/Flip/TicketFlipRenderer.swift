//
//  TicketFlipRenderer.swift
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

struct TicketFlipRenderer: UIViewRepresentable {
    static let sampleCount = 4

    let engine: TicketFlipEngine
    let frontTexture: MTLTexture?
    let backTexture: MTLTexture?
    let stubSize: CGSize
    let edgeStyle: TicketEdgeStyle

    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    func makeUIView(context: Context) -> MTKView {
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
        engine.onWake = { [weak view] in view?.isPaused = false }
        if let device = view.device {
            context.coordinator.configure(device: device,
                                          colorFormat: view.colorPixelFormat,
                                          depthFormat: view.depthStencilPixelFormat)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        let coordinator = context.coordinator
        let needsFrame = coordinator.frontTexture !== frontTexture
            || coordinator.backTexture !== backTexture
            || coordinator.stubSize != stubSize
        coordinator.frontTexture = frontTexture
        coordinator.backTexture = backTexture
        coordinator.stubSize = stubSize
        coordinator.setOutline(size: stubSize, edgeStyle: edgeStyle)
        if needsFrame || coordinator.outlineChanged { uiView.isPaused = false }
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        let engine: TicketFlipEngine
        var frontTexture: MTLTexture?
        var backTexture: MTLTexture?
        var stubSize: CGSize = .zero
        private(set) var outlineChanged = false

        init(engine: TicketFlipEngine) {
            self.engine = engine
        }

        private var commandQueue: MTLCommandQueue!
        private var pipeline: MTLRenderPipelineState!
        private var edgePipeline: MTLRenderPipelineState!
        private var indexBuffer: MTLBuffer!
        private var sampler: MTLSamplerState!
        private var depthState: MTLDepthStencilState!

        private var device: MTLDevice!
        private var outline = TicketFlipEdge.Outline()
        private var outlineBuffer: MTLBuffer?
        private var outlineSize: CGSize = .zero
        private var outlineStyle: TicketEdgeStyle = .scalloped

        func setOutline(size: CGSize, edgeStyle: TicketEdgeStyle) {
            outlineChanged = size.width > 1 && (size != outlineSize || edgeStyle != outlineStyle)
            guard outlineChanged else { return }
            outlineSize = size
            outlineStyle = edgeStyle
            outline = TicketFlipEdge.outline(size: size, edgeStyle: edgeStyle)
            outlineBuffer = outline.vertices.isEmpty ? nil : device?.makeBuffer(
                bytes: outline.vertices,
                length: outline.vertices.count * MemoryLayout<TicketFlipEdge.Vertex>.stride,
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
                  let fragmentFunction = library.makeFunction(name: "ticketFlipFragment") else {
                print("[TicketFlip] shader library unavailable")
                return
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.depthAttachmentPixelFormat = depthFormat
            descriptor.colorAttachments[0].pixelFormat = colorFormat

            descriptor.rasterSampleCount = TicketFlipRenderer.sampleCount
            descriptor.isAlphaToCoverageEnabled = true

            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

            descriptor.vertexFunction = edgeFunction
            edgePipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

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
            engine.step(now: Date())
            let parking = frontTexture != nil && !engine.isAnimating
            view.isPaused = parking
            if parking { engine.park() }

            guard let pipeline, let frontTexture,
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            else { return }

            encoder.setDepthStencilState(depthState)
            encoder.setFragmentTexture(frontTexture, index: 0)
            encoder.setFragmentTexture(backTexture ?? frontTexture, index: 1)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.setCullMode(.none)

            let size = view.bounds.size
            encoder.setRenderPipelineState(pipeline)
            for (face, offset) in [(Float(1), Float(1)), (Float(2), Float(-1))] {
                var uniforms = self.uniforms(viewSize: size, face: face, faceOffset: offset)
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
                                                 edgeCount: Float(range.count))
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<FlipUniforms>.stride, index: 1)
                    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FlipUniforms>.stride, index: 1)
                    encoder.setVertexBufferOffset(
                        range.lowerBound * MemoryLayout<TicketFlipEdge.Vertex>.stride, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0,
                                           vertexCount: (range.count + 1) * 2)
                }
            }
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        private func uniforms(viewSize: CGSize, face: Float, faceOffset: Float,
                              edgeCount: Float = 0) -> FlipUniforms {
            FlipUniforms(
                projection: Self.ortho(width: Float(viewSize.width), height: Float(viewSize.height)),
                lightDir: SIMD4(-0.42, -0.62, 0.86, 0),
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
                gloss: FlipLook.gloss
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
