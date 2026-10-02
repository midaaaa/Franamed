//
//  HallMesh.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 01.10.2026.
//

import CoreGraphics
import Foundation
import Metal
import simd

enum HallMeshShape: Float {
    case seat, rowArm, rowRing, ownArm, ownRing

    var group: Int {
        switch self {
        case .seat: 0
        case .rowArm, .rowRing: 1
        case .ownArm, .ownRing: 2
        }
    }
}

struct HallMesh: @unchecked Sendable {
    let shape: HallMeshShape
    let vertices: MTLBuffer
    let indices: MTLBuffer
    let indexCount: Int
}

struct HallMeshSet: @unchecked Sendable {
    let rows: [[HallMesh]]
    let own: [HallMesh]

    var triangleCount: Int {
        (rows.flatMap { $0 } + own).reduce(0) { $0 + $1.indexCount / 3 }
    }
}

private struct HallMeshGrid {
    var origin: SIMD4<Float>
    var dims: SIMD4<UInt32>
    var limits: SIMD4<UInt32>
}

private struct HallMeshJob {
    let shape: HallMeshShape
    let origin: SIMD3<Float>
    let extent: SIMD3<Float>
    let voxel: Float
}

final class HallMeshBuilder: @unchecked Sendable {
    private static let maxVertices = 600_000
    private static let maxIndices = 3_600_000

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let sample: MTLComputePipelineState
    private let vertex: MTLComputePipelineState
    private let quads: MTLComputePipelineState

    private var samples: MTLBuffer?
    private var cells: MTLBuffer?
    private let vertices: MTLBuffer
    private let indices: MTLBuffer
    private let counts: MTLBuffer

    init?(device: MTLDevice) {
        guard let library = device.makeDefaultLibrary(),
              let queue = device.makeCommandQueue(),
              let sample = library.makeFunction(name: "hallMeshSample")
                .flatMap({ try? device.makeComputePipelineState(function: $0) }),
              let vertex = library.makeFunction(name: "hallMeshVertices")
                .flatMap({ try? device.makeComputePipelineState(function: $0) }),
              let quads = library.makeFunction(name: "hallMeshQuads")
                .flatMap({ try? device.makeComputePipelineState(function: $0) }),
              let vertices = device.makeBuffer(length: Self.maxVertices * 32, options: .storageModePrivate),
              let indices = device.makeBuffer(length: Self.maxIndices * 4, options: .storageModePrivate),
              let counts = device.makeBuffer(length: 8, options: .storageModeShared) else { return nil }
        self.device = device
        self.queue = queue
        self.sample = sample
        self.vertex = vertex
        self.quads = quads
        self.vertices = vertices
        self.indices = indices
        self.counts = counts
    }

    func build(_ scene: HallScene) -> HallMeshSet {
        var args = HallShaderArgs(scene: scene, sample: .dark, size: .zero, frameTop: 0, frameBottom: 1,
                                  sway: .zero, scale: 1)
        let rows = (0..<scene.rowsInFront).map { row in
            Self.rowJobs(scene: scene, row: row).compactMap { mesh(for: $0, args: &args) }
        }
        let own = Self.ownJobs(scene: scene).compactMap { mesh(for: $0, args: &args) }
        return HallMeshSet(rows: rows, own: own)
    }

    private static func rowJobs(scene: HallScene, row: Int) -> [HallMeshJob] {
        let floorY = scene.rowRise * Float(scene.rowsInFront - row - 1)
        let distance = simd_length(SIMD2(scene.rowPitch * Float(row + 1), scene.eye.y - floorY - scene.seatTop))
        let arm = scene.armrestHeight
        let ringZ = -(scene.armrestSetback + scene.armrestLength * 0.5) + 0.11 - scene.armrestLength * 0.5
        return [
            HallMeshJob(shape: .seat, origin: [-0.40, -0.62, -0.30], extent: [0.80, 1.70, 0.40],
                        voxel: min(max(distance * 0.008, 0.008), 0.06)),
            HallMeshJob(shape: .rowArm, origin: [-0.12, -0.02, -0.72], extent: [0.24, arm + 0.05, 0.74],
                        voxel: min(max(distance * 0.006, 0.006), 0.04)),
            HallMeshJob(shape: .rowRing, origin: [-0.06, arm - 0.009, ringZ - 0.06], extent: [0.12, 0.018, 0.12],
                        voxel: min(max(distance * 0.001, 0.0012), 0.004)),
        ]
    }

    private static func ownJobs(scene: HallScene) -> [HallMeshJob] {
        let arm = scene.armrestHeight
        let side = scene.seatPitch * 0.5
        return [-side, side].flatMap { x in
            [HallMeshJob(shape: .ownArm, origin: [x - 0.12, -0.02, -0.89], extent: [0.24, arm + 0.05, 0.98], voxel: 0.010),
             HallMeshJob(shape: .ownRing, origin: [x - 0.06, arm - 0.009, -0.80], extent: [0.12, 0.018, 0.12], voxel: 0.0012)]
        }
    }

    private func mesh(for job: HallMeshJob, args: inout HallShaderArgs) -> HallMesh? {
        let dims = SIMD3<UInt32>((job.extent / job.voxel).rounded(.up))
        let pointCount = Int((dims.x + 1) * (dims.y + 1) * (dims.z + 1))
        let cellCount = Int(dims.x * dims.y * dims.z)
        guard let samples = scratch(&self.samples, length: pointCount * 4),
              let cells = scratch(&self.cells, length: cellCount * 4),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        var grid = HallMeshGrid(origin: SIMD4(job.origin, job.voxel),
                                dims: SIMD4(dims, UInt32(job.shape.rawValue)),
                                limits: SIMD4(UInt32(Self.maxVertices), UInt32(Self.maxIndices), 0, 0))
        counts.contents().initializeMemory(as: UInt32.self, repeating: 0, count: 2)

        encoder.setBuffer(samples, offset: 0, index: 0)
        encoder.setBytes(&args, length: MemoryLayout<HallShaderArgs>.stride, index: 1)
        encoder.setBytes(&grid, length: MemoryLayout<HallMeshGrid>.stride, index: 2)
        encoder.setBuffer(cells, offset: 0, index: 3)
        encoder.setBuffer(counts, offset: 0, index: 5)

        let points = MTLSize(width: Int(dims.x + 1), height: Int(dims.y + 1), depth: Int(dims.z + 1))
        let group = MTLSize(width: 8, height: 8, depth: 4)
        encoder.setComputePipelineState(sample)
        encoder.dispatchThreads(points, threadsPerThreadgroup: group)
        encoder.setComputePipelineState(vertex)
        encoder.setBuffer(vertices, offset: 0, index: 4)
        encoder.dispatchThreads(MTLSize(width: Int(dims.x), height: Int(dims.y), depth: Int(dims.z)),
                                threadsPerThreadgroup: group)
        encoder.setComputePipelineState(quads)
        encoder.setBuffer(indices, offset: 0, index: 4)
        encoder.dispatchThreads(points, threadsPerThreadgroup: group)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let result = counts.contents().bindMemory(to: UInt32.self, capacity: 2)
        let vertexCount = min(Int(result[0]), Self.maxVertices)
        let indexCount = min(Int(result[1]), Self.maxIndices)
        if Int(result[0]) > Self.maxVertices || Int(result[1]) > Self.maxIndices {
            NSLog("[Hall] mesh %d overflow: %d vertices, %d indices", Int(job.shape.rawValue), result[0], result[1])
        }
        guard indexCount > 0,
              let finalVertices = device.makeBuffer(length: vertexCount * 32, options: .storageModePrivate),
              let finalIndices = device.makeBuffer(length: indexCount * 4, options: .storageModePrivate),
              let copyBuffer = queue.makeCommandBuffer(),
              let blit = copyBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: vertices, sourceOffset: 0, to: finalVertices, destinationOffset: 0, size: vertexCount * 32)
        blit.copy(from: indices, sourceOffset: 0, to: finalIndices, destinationOffset: 0, size: indexCount * 4)
        blit.endEncoding()
        copyBuffer.commit()
        copyBuffer.waitUntilCompleted()
        return HallMesh(shape: job.shape, vertices: finalVertices, indices: finalIndices, indexCount: indexCount)
    }

    private func scratch(_ buffer: inout MTLBuffer?, length: Int) -> MTLBuffer? {
        if let buffer, buffer.length >= length { return buffer }
        buffer = device.makeBuffer(length: length, options: .storageModePrivate)
        return buffer
    }
}

@MainActor
final class HallMeshStore {
    static let shared = HallMeshStore()

    private var scene: HallScene?
    private var meshes: HallMeshSet?
    private var building: HallScene?
    private var waiters: [() -> Void] = []

    func meshes(for scene: HallScene, ready: @escaping () -> Void) -> HallMeshSet? {
        if self.scene == scene, let meshes { return meshes }
        guard let device = HallRenderer.shared?.device else { return nil }
        waiters.append(ready)
        guard building != scene else { return nil }
        building = scene
        Task.detached(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            let set = HallMeshBuilder(device: device)?.build(scene)
            let seconds = CFAbsoluteTimeGetCurrent() - start
            await HallMeshStore.shared.finish(scene: scene, set: set, seconds: seconds)
        }
        return nil
    }

    func meshes(for scene: HallScene) async -> HallMeshSet? {
        guard HallRenderer.shared != nil else { return nil }
        return await withCheckedContinuation { continuation in
            let ready = meshes(for: scene) { [weak self] in
                continuation.resume(returning: self?.scene == scene ? self?.meshes : nil)
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    private func finish(scene: HallScene, set: HallMeshSet?, seconds: Double) {
        guard building == scene else { return }
        building = nil
        self.scene = scene
        meshes = set
        if let set {
            NSLog("[Hall] meshes built in %.0f ms, %d triangles", seconds * 1000, set.triangleCount)
        }
        let waiters = self.waiters
        self.waiters = []
        waiters.forEach { $0() }
    }
}
