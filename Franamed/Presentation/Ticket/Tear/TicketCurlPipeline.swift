//
//  TicketCurlPipeline.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.09.2026.
//

import SwiftUI
import Metal
import simd

final class TicketCurlPipeline {

    private let skinPipeline: MTLRenderPipelineState
    private let edgePipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let indexBuffer: MTLBuffer
    private let device: MTLDevice

    private var outline = EdgeOutline.Outline()
    private var outlineBuffer: MTLBuffer?
    private var outlineKey: OutlineKey?

    private struct OutlineKey: Equatable {
        let shape: AnyHashable
        let size: CGSize
        let side: StubSide
        let extent: CGFloat
    }

    init?(device: MTLDevice, library: MTLLibrary, colorFormat: MTLPixelFormat,
          depthFormat: MTLPixelFormat, sampleCount: Int) {
        let indices = TicketCurlTopology.makeIndices()
        guard let indexBuffer = device.makeBuffer(bytes: indices,
                                                  length: indices.count * MemoryLayout<UInt16>.stride,
                                                  options: .storageModeShared),
              let skinVertex = library.makeFunction(name: "ticketCurlVertex"),
              let skinFragment = library.makeFunction(name: "ticketCurlFragment"),
              let edgeVertex = library.makeFunction(name: "ticketCurlEdgeVertex"),
              let edgeFragment = library.makeFunction(name: "ticketCurlEdgeFragment") else {
            print("[TicketCurl] shader library unavailable")
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.depthAttachmentPixelFormat = depthFormat
        descriptor.rasterSampleCount = sampleCount

        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = colorFormat
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            descriptor.vertexFunction = skinVertex
            descriptor.fragmentFunction = skinFragment
            self.skinPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

            descriptor.vertexFunction = edgeVertex
            descriptor.fragmentFunction = edgeFragment
            self.edgePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("[TicketCurl] pipeline state creation failed: \(error)")
            return nil
        }

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }

        self.device = device
        self.indexBuffer = indexBuffer
        self.depthState = depthState
    }

    // MARK: Stub outline

    func setOutline(shape: (any Shape & Hashable)?, config: TicketTearConfig, ticketSize: CGSize) {
        guard let shape, ticketSize.width > 1, ticketSize.height > 1 else {
            outline = EdgeOutline.Outline()
            outlineBuffer = nil
            outlineKey = nil
            return
        }

        let key = OutlineKey(shape: AnyHashable(shape), size: ticketSize,
                             side: config.stubSide, extent: config.stubExtent)
        guard key != outlineKey else { return }
        outlineKey = key

        let geometry = TearGeometry(config: config, size: ticketSize, fromStart: true)
        let frame = Self.stubFrame(config: config, ticketSize: ticketSize)
        let path = shape.path(in: frame).cgPath

        outline = EdgeOutline.outline(of: path) { p in
            let d = p - geometry.lineStart
            return CGPoint(x: d • geometry.axisDir, y: d • geometry.stubN)
        }
        outlineBuffer = outline.vertices.isEmpty ? nil : device.makeBuffer(
            bytes: outline.vertices,
            length: outline.vertices.count * MemoryLayout<EdgeOutline.Vertex>.stride,
            options: .storageModeShared)
    }

    static func stubFrame(config: TicketTearConfig, ticketSize: CGSize) -> CGRect {
        let e = config.stubExtent
        switch config.stubSide {
        case .trailing: return CGRect(x: ticketSize.width - e, y: 0, width: e, height: ticketSize.height)
        case .leading:  return CGRect(x: 0, y: 0, width: e, height: ticketSize.height)
        case .bottom:   return CGRect(x: 0, y: ticketSize.height - e, width: ticketSize.width, height: e)
        case .top:      return CGRect(x: 0, y: 0, width: ticketSize.width, height: e)
        }
    }

    // MARK: Encoding

    func encode(into encoder: MTLRenderCommandEncoder, uniforms: CurlUniforms, pose: TearPose,
                texture: MTLTexture) {
        var uniforms = uniforms
        let stride = MemoryLayout<CurlUniforms>.stride
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBytes(&uniforms, length: stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: stride, index: 1)

        if uniforms.thickness > 0.01, let outlineBuffer {
            encoder.setRenderPipelineState(edgePipeline)
            encoder.setCullMode(.none)
            for range in outline.ranges {
                var count = Float(range.count)
                encoder.setVertexBuffer(outlineBuffer,
                                        offset: range.lowerBound * MemoryLayout<EdgeOutline.Vertex>.stride,
                                        index: 0)
                encoder.setVertexBytes(&count, length: MemoryLayout<Float>.stride, index: 2)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0,
                                       vertexCount: (range.count + 1) * 2)
            }
        }

        let flatWinding = pose.stubN.dx * pose.perfDir.dy - pose.stubN.dy * pose.perfDir.dx
        encoder.setFrontFacing(flatWinding > 0 ? .clockwise : .counterClockwise)
        encoder.setRenderPipelineState(skinPipeline)
        encoder.setFragmentTexture(texture, index: 0)

        for (skin, cull) in [(Float(1), MTLCullMode.back), (Float(-1), MTLCullMode.front)] {
            var skin = skin
            encoder.setVertexBytes(&skin, length: MemoryLayout<Float>.stride, index: 2)
            encoder.setCullMode(cull)
            encoder.drawIndexedPrimitives(type: .triangle,
                                          indexCount: TicketCurlTopology.indexCount,
                                          indexType: .uint16,
                                          indexBuffer: indexBuffer,
                                          indexBufferOffset: 0)
        }
    }

    // MARK: Uniforms

    static func uniforms(for pose: TearPose, config: TicketTearConfig, ticketSize: CGSize,
                         canvasPadding: CGFloat, viewSize: CGSize) -> CurlUniforms {
        CurlUniforms(
            projection: orthoProjection(width: Float(viewSize.width), height: Float(viewSize.height)),
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
            thickness: Float(max(config.thickness, 0)),

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

            paperBack: rgba(config.backColor))
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
