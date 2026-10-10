//
//  HallRenderer.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 01.10.2026.
//

import Metal
import QuartzCore
import UIKit

final class HallRenderer: @unchecked Sendable {
    struct Frame: @unchecked Sendable {
        let sample: HallFrameSample
        let scene: HallScene
        let args: HallShaderArgs
        let meshes: HallMeshSet
        var picture: HallPicture?
        var phone: HallPhoneDraw?
    }

    private struct MeshDraw {
        var row: SIMD4<Float>
        var instance: SIMD4<Float>
    }

    private struct Targets {
        let color: MTLTexture
        let depth: MTLTexture
    }

    static let shared = MTLCreateSystemDefaultDevice().flatMap(HallRenderer.init)

    private static let sampleCount = 4
    private static let phonePerimeterSegments = 160
    private static let buttonSegments = 24

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let meshPipelines: [MTLRenderPipelineState]
    private let picturePipeline: MTLRenderPipelineState
    private let phonePipeline: MTLRenderPipelineState
    private let phoneSidePipeline: MTLRenderPipelineState
    private let phoneButtonPipelines: [MTLRenderPipelineState]
    private let phoneGlowPipeline: MTLRenderPipelineState
    private let screenGlowPipeline: MTLRenderPipelineState
    private let veilPipeline: MTLRenderPipelineState
    private let screenGlowDepth: MTLDepthStencilState
    private let blankPicture: MTLTexture
    private let clearPicture: MTLTexture
    private let depthState: MTLDepthStencilState
    private let queue = DispatchQueue(label: "hall.render", qos: .userInteractive)
    private var targets: [SIMD2<Int>: Targets] = [:]
    private var lens: MTLTexture?
    private var grid: (sample: HallFrameSample, buffer: MTLBuffer)?

    private init?(device: MTLDevice) {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.rasterSampleCount = Self.sampleCount
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let library = device.makeDefaultLibrary(),
              let commandQueue = device.makeCommandQueue(),
              let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }

        descriptor.vertexFunction = library.makeFunction(name: "hallMeshVertex")
        let meshPipelines = (0..<3).compactMap { group -> MTLRenderPipelineState? in
            let constants = MTLFunctionConstantValues()
            var value = Int32(group)
            constants.setConstantValue(&value, type: .int, index: 0)
            descriptor.fragmentFunction = try? library.makeFunction(name: "hallMeshFragment", constantValues: constants)
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        descriptor.vertexFunction = library.makeFunction(name: "hallPictureVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "hallPictureFragment")
        let picturePipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

        descriptor.vertexFunction = library.makeFunction(name: "hallPhoneVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "hallPhoneFragment")
        let blend = descriptor.colorAttachments[0]!
        blend.isBlendingEnabled = true
        blend.sourceRGBBlendFactor = .one
        blend.sourceAlphaBlendFactor = .one
        blend.destinationRGBBlendFactor = .oneMinusSourceAlpha
        blend.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let phonePipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.vertexFunction = library.makeFunction(name: "hallPhoneSideVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "hallPhoneMetalFragment")
        let phoneSidePipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        let phoneButtonPipelines = ["hallPhoneButtonRimVertex", "hallPhoneButtonCapVertex"].compactMap { name in
            descriptor.vertexFunction = library.makeFunction(name: name)
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        blend.destinationRGBBlendFactor = .one
        blend.destinationAlphaBlendFactor = .one
        descriptor.vertexFunction = library.makeFunction(name: "hallPhoneGlowVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "hallPhoneGlowFragment")
        let phoneGlowPipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.vertexFunction = library.makeFunction(name: "hallScreenGlowVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "hallScreenGlowFragment")
        let screenGlowPipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        blend.sourceRGBBlendFactor = .zero
        blend.sourceAlphaBlendFactor = .zero
        blend.destinationRGBBlendFactor = .oneMinusSourceAlpha
        blend.destinationAlphaBlendFactor = .one
        descriptor.fragmentFunction = library.makeFunction(name: "hallVeilFragment")
        let veilPipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        let glow = MTLDepthStencilDescriptor()
        glow.depthCompareFunction = .always
        glow.isDepthWriteEnabled = false
        let screenGlowDepth = device.makeDepthStencilState(descriptor: glow)

        let blank = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1,
                                                             mipmapped: false)
        guard meshPipelines.count == 3, let picturePipeline, let phonePipeline, let phoneSidePipeline, phoneButtonPipelines.count == 2,
              let phoneGlowPipeline, let screenGlowPipeline, let veilPipeline, let screenGlowDepth,
              let blankPicture = device.makeTexture(descriptor: blank),
              let clearPicture = device.makeTexture(descriptor: blank) else { return nil }
        var black: UInt32 = 0xFF00_0000
        blankPicture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)

        self.device = device
        self.commandQueue = commandQueue
        self.meshPipelines = meshPipelines
        self.picturePipeline = picturePipeline
        self.phonePipeline = phonePipeline
        self.phoneSidePipeline = phoneSidePipeline
        self.phoneButtonPipelines = phoneButtonPipelines
        self.phoneGlowPipeline = phoneGlowPipeline
        self.screenGlowPipeline = screenGlowPipeline
        self.veilPipeline = veilPipeline
        self.screenGlowDepth = screenGlowDepth
        self.blankPicture = blankPicture
        var clear: UInt32 = 0
        clearPicture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &clear, bytesPerRow: 4)
        self.clearPicture = clearPicture
        self.depthState = depthState
    }

    func present(_ frame: Frame, to drawable: CAMetalDrawable) {
        queue.sync {
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  encode(frame, target: drawable.texture, commandBuffer: commandBuffer) else { return }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    func snapshot(_ frame: Frame, width: Int, height: Int) async -> CGImage? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.image(frame, width: width, height: height)) }
        }
    }

    private func image(_ frame: Frame, width: Int, height: Int) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        guard width > 0, height > 0, let target = device.makeTexture(descriptor: descriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              encode(frame, target: target, commandBuffer: commandBuffer) else { return nil }
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

    private func encode(_ frame: Frame, target: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let grid = gridBuffer(for: frame.sample) else { return false }
        var screen: MTLTexture?
        if let draw = frame.phone, draw.screenOn > 0.001 {
            if draw.reusesLens, let lens, lens.width == draw.lensWidth, lens.height == draw.lensHeight {
                screen = lens
            } else if let lens = lensTexture(width: draw.lensWidth, height: draw.lensHeight),
                      let encoder = hallPass(frame, args: draw.lensArgs, target: lens, grid: grid,
                                             commandBuffer: commandBuffer) {
                encoder.endEncoding()
                screen = lens
            }
        }
        guard let encoder = hallPass(frame, args: frame.args, target: target, grid: grid,
                                     commandBuffer: commandBuffer) else { return false }
        if frame.args.glow.x > 0 || frame.args.glow.y > 0 {
            encoder.setCullMode(.none)
            encoder.setDepthStencilState(screenGlowDepth)
            if frame.args.glow.x > 0 {
                encoder.setRenderPipelineState(screenGlowPipeline)
                encoder.setFragmentTexture(frame.picture?.texture ?? blankPicture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            if frame.args.glow.y > 0 {
                encoder.setRenderPipelineState(veilPipeline)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            encoder.setDepthStencilState(depthState)
        }
        if let phone = frame.phone {
            var args = phone.args
            encoder.setCullMode(.none)
            encoder.setVertexBytes(&args, length: MemoryLayout<HallPhoneArgs>.stride, index: 2)
            encoder.setFragmentBytes(&args, length: MemoryLayout<HallPhoneArgs>.stride, index: 2)
            encoder.setRenderPipelineState(phoneSidePipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0,
                                   vertexCount: 2 * (Self.phonePerimeterSegments + 1))
            encoder.setRenderPipelineState(phoneButtonPipelines[0])
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 2 * (Self.buttonSegments + 1),
                                   instanceCount: 4)
            encoder.setRenderPipelineState(phoneButtonPipelines[1])
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3 * Self.buttonSegments,
                                   instanceCount: 4)
            encoder.setRenderPipelineState(phonePipeline)
            encoder.setFragmentTexture(screen ?? clearPicture, index: 0)
            encoder.setFragmentTexture(phone.chrome?.texture ?? clearPicture, index: 1)
            encoder.setFragmentTexture(phone.turnedChrome?.texture ?? phone.chrome?.texture ?? clearPicture, index: 2)
            encoder.setFragmentTexture(phone.thumbnail?.texture ?? clearPicture, index: 3)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            if phone.args.glow.w > 0 {
                encoder.setDepthStencilState(screenGlowDepth)
                encoder.setRenderPipelineState(phoneGlowPipeline)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.setDepthStencilState(depthState)
            }
        }
        encoder.endEncoding()
        return true
    }

    private func hallPass(_ frame: Frame, args: HallShaderArgs, target: MTLTexture, grid: MTLBuffer,
                          commandBuffer: MTLCommandBuffer) -> MTLRenderCommandEncoder? {
        guard let targets = meshTargets(width: target.width, height: target.height) else { return nil }
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
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        var args = args
        var viewport = SIMD4<Float>(Float(target.width), Float(target.height), 0, 0)
        encoder.setDepthStencilState(depthState)
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBytes(&args, length: MemoryLayout<HallShaderArgs>.stride, index: 1)
        encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
        encoder.setFragmentBytes(&args, length: MemoryLayout<HallShaderArgs>.stride, index: 0)
        encoder.setFragmentBuffer(grid, offset: 0, index: 1)

        encoder.setRenderPipelineState(picturePipeline)
        encoder.setFragmentTexture(frame.picture?.texture ?? blankPicture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.setCullMode(.back)

        for mesh in frame.meshes.own {
            draw(mesh, row: .zero, firstSeat: 0, seats: 1, encoder: encoder)
        }
        let scene = frame.scene
        let viewSlope = Self.halfWidthSlope(args: args, width: Float(target.width))
        let swayX = args.eye.x - scene.eye.x
        for (index, rowMeshes) in frame.meshes.rows.enumerated() {
            let distance = scene.eye.z - scene.rowPitch * Float(index + 1)
            let floorY = scene.rowRise * Float(scene.rowsInFront - index - 1)
            let offset: Float = index % 2 == 0 ? scene.seatPitch * 0.5 : 0
            let reach = Self.visibleHalfWidth(viewSlope: viewSlope, depth: scene.eye.z - distance + 0.8,
                                              radius: distance + HallScene.rowArc) + abs(swayX) + 0.5
            for mesh in rowMeshes {
                let center = offset + (mesh.shape == .seat ? 0 : scene.seatPitch * 0.5)
                let first = ((-reach - center) / scene.seatPitch).rounded(.down)
                let last = ((reach - center) / scene.seatPitch).rounded(.up)
                draw(mesh, row: SIMD4(center, floorY, distance, distance + HallScene.rowArc), firstSeat: first,
                     seats: Int(last - first) + 1, encoder: encoder)
            }
        }
        return encoder
    }

    private func draw(_ mesh: HallMesh, row: SIMD4<Float>, firstSeat: Float, seats: Int,
                      encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(meshPipelines[mesh.shape.group])
        var draw = MeshDraw(row: row, instance: SIMD4(mesh.shape.rawValue, firstSeat, 0, 0))
        encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&draw, length: MemoryLayout<MeshDraw>.stride, index: 2)
        encoder.setFragmentBytes(&draw, length: MemoryLayout<MeshDraw>.stride, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount, indexType: .uint32,
                                      indexBuffer: mesh.indices, indexBufferOffset: 0, instanceCount: seats)
    }

    private func gridBuffer(for sample: HallFrameSample) -> MTLBuffer? {
        if let grid, grid.sample == sample { return grid.buffer }
        let values = sample.blurredInterleaved
        guard let buffer = device.makeBuffer(bytes: values, length: values.count * MemoryLayout<Float>.stride,
                                             options: .storageModeShared) else { return nil }
        grid = (sample, buffer)
        return buffer
    }

    private func meshTargets(width: Int, height: Int) -> Targets? {
        let key = SIMD2(width, height)
        if let cached = targets[key] { return cached }
        func texture(_ format: MTLPixelFormat) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width,
                                                                      height: height, mipmapped: false)
            descriptor.textureType = .type2DMultisample
            descriptor.sampleCount = Self.sampleCount
            descriptor.usage = .renderTarget
            descriptor.storageMode = .memoryless
            return device.makeTexture(descriptor: descriptor)
        }
        guard let color = texture(.bgra8Unorm), let depth = texture(.depth32Float) else { return nil }
        if targets.count >= 3 { targets.removeAll() }
        let made = Targets(color: color, depth: depth)
        targets[key] = made
        return made
    }

    private func lensTexture(width: Int, height: Int) -> MTLTexture? {
        if let lens, lens.width == width, lens.height == height { return lens }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard width > 0, height > 0 else { return nil }
        lens = device.makeTexture(descriptor: descriptor)
        return lens
    }

    private static func halfWidthSlope(args: HallShaderArgs, width: Float) -> Float {
        let focal = args.camera.x, centerX = args.camera.z
        return max(centerX, width - centerX) / max(focal, 1)
    }

    private static func visibleHalfWidth(viewSlope: Float, depth: Float, radius: Float) -> Float {
        let flat = viewSlope * depth
        return viewSlope * (depth + flat * flat / (2 * radius))
    }
}

@MainActor
enum HallSnapshot {
    static func image(sample: HallFrameSample, scene: HallScene, size: CGSize, frameTop: CGFloat,
                      frameBottom: CGFloat, scale: CGFloat) async -> UIImage? {
        guard let renderer = HallRenderer.shared,
              let meshes = await HallMeshStore.shared.meshes(for: scene) else { return nil }
        let args = HallShaderArgs(scene: scene, sample: sample, size: size, frameTop: frameTop,
                                  frameBottom: frameBottom, sway: .zero, scale: scale)
        let frame = HallRenderer.Frame(sample: sample, scene: scene, args: args, meshes: meshes)
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        return await renderer.snapshot(frame, width: width, height: height).map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
    }
}
