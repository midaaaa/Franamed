//
//  HallMetalView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 01.10.2026.
//

import MetalKit
import SwiftUI

struct HallMetalView: UIViewRepresentable {
    let sample: HallFrameSample
    let scene: HallScene
    let size: CGSize
    let frameTop: CGFloat
    let frameBottom: CGFloat
    let motion: HallMotion

    struct Key: Equatable {
        let sample: HallFrameSample
        let scene: HallScene
        let size: CGSize
        let frameTop: CGFloat
        let frameBottom: CGFloat
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.delegate = context.coordinator
        if let device = view.device { context.coordinator.configure(device: device) }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let key = Key(sample: sample, scene: scene, size: size, frameTop: frameTop, frameBottom: frameBottom)
        context.coordinator.attach(motion, view: view)
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.attach(nil, view: view)
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var key: Key?

        private var renderer: HallRenderer?
        private weak var motion: HallMotion?

        func configure(device: MTLDevice) {
            renderer = HallRenderer(device: device)
        }

        func attach(_ motion: HallMotion?, view: MTKView) {
            guard self.motion !== motion else { return }
            self.motion?.onSway = nil
            self.motion = motion
            motion?.onSway = { [weak self, weak view] _ in
                guard let self, let view else { return }
                self.render(in: view)
            }
        }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            MainActor.assumeIsolated { view.setNeedsDisplay() }
        }

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated { render(in: view) }
        }

        private func render(in view: MTKView) {
            guard let key, let renderer, let layer = view.layer as? CAMetalLayer else { return }
            let sway = motion?.sway ?? .zero
            let drawableSize = layer.drawableSize
            guard drawableSize.height > 0 else { return }
            let pixelScale = drawableSize.height / max(view.bounds.height, 1)
            var frame = HallRenderer.Frame(
                sample: key.sample, scene: key.scene,
                args: HallShaderArgs(scene: key.scene, sample: key.sample, size: key.size,
                                     frameTop: key.frameTop, frameBottom: key.frameBottom,
                                     sway: sway, scale: pixelScale),
                meshes: nil)
            frame.meshes = HallMeshStore.shared.meshes(for: key.scene, device: renderer.device) { [weak view] in
                view?.setNeedsDisplay()
            }
            renderer.submit(frame, to: HallRenderer.LayerBox(layer: layer))
        }

    }
}

final class HallRenderer: @unchecked Sendable {
    struct Frame: @unchecked Sendable {
        let sample: HallFrameSample
        let scene: HallScene
        var args: HallShaderArgs
        var meshes: HallMeshSet?
    }

    struct LayerBox: @unchecked Sendable {
        let layer: CAMetalLayer
    }

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    private let queue = DispatchQueue(label: "hall.render", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: (frame: Frame, layer: LayerBox)?
    private var scheduled = false

    private var pipeline: MTLComputePipelineState?
    private var meshPipelines: [MTLRenderPipelineState] = []
    private var occluderPipeline: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var targets: (color: MTLTexture, depth: MTLTexture)?
    private var grid: MTLBuffer?
    private var gridSample: HallFrameSample?

    init(device: MTLDevice) {
        self.device = device
        commandQueue = device.makeCommandQueue()
        guard let library = device.makeDefaultLibrary() else {
            NSLog("[Hall] shader library unavailable")
            return
        }
        pipeline = library.makeFunction(name: "cinemaHallKernel")
            .flatMap { try? device.makeComputePipelineState(function: $0) }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.rasterSampleCount = HallMeshPass.samples
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.vertexFunction = library.makeFunction(name: "hallMeshVertex")
        meshPipelines = (0..<3).compactMap { group in
            let constants = MTLFunctionConstantValues()
            var value = Int32(group)
            constants.setConstantValue(&value, type: .int, index: 0)
            descriptor.fragmentFunction = try? library.makeFunction(name: "hallMeshFragment", constantValues: constants)
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        descriptor.vertexFunction = library.makeFunction(name: "hallMeshOccluder")
        descriptor.fragmentFunction = library.makeFunction(name: "hallMeshBlack")
        occluderPipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depth)
    }

    func submit(_ frame: Frame, to layer: LayerBox) {
        lock.lock()
        pending = (frame, layer)
        let start = !scheduled
        scheduled = true
        lock.unlock()
        if start { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let next = pending else {
                scheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            draw(next.frame, layer: next.layer.layer)
        }
    }

    func snapshot(_ frame: Frame, width: Int, height: Int) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderWrite]
        descriptor.storageMode = .shared
        guard width > 0, height > 0, let target = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue?.makeCommandBuffer() else { return nil }
        encode(frame, target: target, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            target.getBytes(base, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    private func draw(_ frame: Frame, layer: CAMetalLayer) {
        guard let drawable = layer.nextDrawable(), let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        encode(frame, target: drawable.texture, commandBuffer: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func encode(_ frame: Frame, target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        if gridSample != frame.sample {
            grid = device.makeBuffer(bytes: frame.sample.blurredInterleaved,
                                     length: frame.sample.blurredInterleaved.count * MemoryLayout<Float>.stride,
                                     options: .storageModeShared)
            gridSample = frame.sample
        }
        var args = frame.args
        let meshEncoded = frame.meshes.map {
            encodeMesh($0, frame: frame, args: &args, target: target, commandBuffer: commandBuffer)
        }
        if meshEncoded != true, let pipeline, let encoder = commandBuffer.makeComputeCommandEncoder() {
            encodeKernel(encoder, pipeline: pipeline, args: &args, target: target)
        }
    }

    private func encodeKernel(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState,
                              args: inout HallShaderArgs, target: MTLTexture) {
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(target, index: 0)
        encoder.setBytes(&args, length: MemoryLayout<HallShaderArgs>.stride, index: 0)
        encoder.setBuffer(grid, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
    }

    private func encodeMesh(_ meshes: HallMeshSet, frame: Frame, args: inout HallShaderArgs,
                            target: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        let scene = frame.scene
        guard meshPipelines.count == 3, let occluderPipeline, let depthState,
              let targets = meshTargets(width: target.width, height: target.height) else {
            return false
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.color
        pass.colorAttachments[0].resolveTexture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = targets.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }

        var viewport = SIMD4<Float>(Float(target.width), Float(target.height), 0, 0)
        encoder.setDepthStencilState(depthState)
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBytes(&args, length: MemoryLayout<HallShaderArgs>.stride, index: 1)
        encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
        encoder.setFragmentBytes(&args, length: MemoryLayout<HallShaderArgs>.stride, index: 0)
        encoder.setFragmentBuffer(grid, offset: 0, index: 1)

        encoder.setRenderPipelineState(occluderPipeline)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.setCullMode(.back)

        for mesh in meshes.own {
            draw(mesh, row: .zero, firstSeat: 0, seats: 1, rowIndex: -1, encoder: encoder)
        }
        let viewSlope = HallMeshPass.halfWidthRatio(args: args, width: Float(target.width))
        let swayX = args.eyeRows.x - scene.eye.x
        for (rowIndex, rowMeshes) in meshes.rows.enumerated() {
            let distance = scene.eye.z - scene.rowPitch * Float(rowIndex + 1)
            let floorY = scene.rowRise * Float(scene.rowsInFront - rowIndex - 1)
            let offset: Float = rowIndex % 2 == 0 ? scene.seatPitch * 0.5 : 0
            let reach = HallMeshPass.visibleHalfWidth(viewSlope: viewSlope, depth: scene.eye.z - distance + 0.8,
                                                      radius: distance + HallScene.rowArc) + abs(swayX) + 0.5
            for mesh in rowMeshes {
                let center = offset + (mesh.shape == .seat ? 0 : scene.seatPitch * 0.5)
                let first = ((-reach - center) / scene.seatPitch).rounded(.down)
                let last = ((reach - center) / scene.seatPitch).rounded(.up)
                draw(mesh, row: SIMD4(center, floorY, distance, distance + HallScene.rowArc), firstSeat: first,
                     seats: Int(last - first) + 1, rowIndex: rowIndex, encoder: encoder)
            }
        }
        encoder.endEncoding()
        return true
    }

    private func draw(_ mesh: HallMesh, row: SIMD4<Float>, firstSeat: Float, seats: Int, rowIndex: Int,
                      encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(meshPipelines[mesh.shape.group])
        var draw = HallMeshPass.Draw(row: row, instance: SIMD4(mesh.shape.rawValue, firstSeat, Float(rowIndex), 0))
        encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&draw, length: MemoryLayout<HallMeshPass.Draw>.stride, index: 2)
        encoder.setFragmentBytes(&draw, length: MemoryLayout<HallMeshPass.Draw>.stride, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount, indexType: .uint32,
                                      indexBuffer: mesh.indices, indexBufferOffset: 0, instanceCount: seats)
    }

    private func meshTargets(width: Int, height: Int) -> (color: MTLTexture, depth: MTLTexture)? {
        if let targets, targets.color.width == width, targets.color.height == height { return targets }
        func texture(_ format: MTLPixelFormat) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width,
                                                                      height: height, mipmapped: false)
            descriptor.textureType = .type2DMultisample
            descriptor.sampleCount = HallMeshPass.samples
            descriptor.usage = .renderTarget
            descriptor.storageMode = .memoryless
            return device.makeTexture(descriptor: descriptor)
        }
        guard let color = texture(.bgra8Unorm), let depth = texture(.depth32Float) else { return nil }
        targets = (color, depth)
        return targets
    }
}

enum HallMeshPass {
    static let samples = 4

    struct Draw {
        var row: SIMD4<Float>
        var instance: SIMD4<Float>
    }

    static func halfWidthRatio(args: HallShaderArgs, width: Float) -> Float {
        let focal = args.camera.x, centerX = args.camera.z
        return max(centerX, width - centerX) / max(focal, 1)
    }

    static func visibleHalfWidth(viewSlope: Float, depth: Float, radius: Float) -> Float {
        let flat = viewSlope * depth
        return viewSlope * (depth + flat * flat / (2 * radius))
    }
}

@MainActor
enum HallSnapshot {
    private static let renderer = MTLCreateSystemDefaultDevice().map { HallRenderer(device: $0) }

    static func image(sample: HallFrameSample, scene: HallScene, size: CGSize, frameTop: CGFloat,
                      frameBottom: CGFloat, scale: CGFloat) async -> UIImage? {
        guard let renderer,
              let meshes = await HallMeshStore.shared.meshes(for: scene, device: renderer.device) else { return nil }
        let frame = HallRenderer.Frame(
            sample: sample, scene: scene,
            args: HallShaderArgs(scene: scene, sample: sample, size: size, frameTop: frameTop,
                                 frameBottom: frameBottom, sway: .zero, scale: scale),
            meshes: meshes)
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        return renderer.snapshot(frame, width: width, height: height).map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
    }
}
