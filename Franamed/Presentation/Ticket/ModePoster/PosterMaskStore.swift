//
//  PosterMaskStore.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 27.10.2026.
//

import CoreImage
import CryptoKit
import os
import UIKit
import Vision

struct PosterMask: Sendable {
    let image: UIImage?
    let mean: Float
}

final class PosterMaskStore: @unchecked Sendable {
    nonisolated static let shared = PosterMaskStore()

    private static let root = "PosterMasks2"
    private static let directory = "PosterMasks2/Lit"
    private static let maskSize = CGSize(width: 128, height: 192)

    private final class Entry {
        let mask: PosterMask
        init(_ mask: PosterMask) { self.mask = mask }
    }

    private nonisolated(unsafe) let memory = NSCache<NSURL, Entry>()
    private nonisolated let inFlight = OSAllocatedUnfairLock(initialState: [URL: Task<PosterMask, Never>]())
    private nonisolated let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

    private nonisolated init() {}

    private static let analysisWidth: CGFloat = 384
    private static let minimumInstanceShare = 0.02
    private static let coverageRange = 0.03...0.7
    private static let backgroundFloor: CGFloat = 0.4
    private static let darkBackgroundShare: CGFloat = 0.35

    nonisolated func memoryMask(for url: URL) -> PosterMask? {
        memory.object(forKey: url as NSURL)?.mask
    }

    nonisolated func cachedMask(for url: URL) -> PosterMask? {
        if let entry = memory.object(forKey: url as NSURL) { return entry.mask }
        guard let data = try? Data(contentsOf: fileURL(for: url)), data.count >= 4 else { return nil }
        let mean = data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        let mask = PosterMask(image: data.count > 4 ? UIImage(data: data.dropFirst(4)) : nil, mean: mean)
        memory.setObject(Entry(mask), forKey: url as NSURL)
        return mask
    }

    nonisolated func mask(for url: URL, image: UIImage) async -> PosterMask {
        if let cached = cachedMask(for: url) { return cached }
        let task = inFlight.withLock { running in
            if let task = running[url] { return task }
            let task = Task.detached(priority: .utility) { Self.makeMask(from: image) }
            running[url] = task
            return task
        }
        let made = await task.value
        inFlight.withLock { $0[url] = nil }
        memory.setObject(Entry(made), forKey: url as NSURL)
        let folder = caches.appendingPathComponent(Self.directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var data = withUnsafeBytes(of: made.mean) { Data($0) }
        data.append(made.image?.pngData() ?? Data())
        try? data.write(to: fileURL(for: url))
        return made
    }

    nonisolated func removeAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: caches.appendingPathComponent(Self.root, isDirectory: true))
    }

    private nonisolated func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return caches.appendingPathComponent(Self.directory, isDirectory: true)
            .appendingPathComponent(digest).appendingPathExtension("png")
    }

    // MARK: Vision

    private nonisolated static func makeMask(from image: UIImage) -> PosterMask {
        guard let source = image.cgImage else { return PosterMask(image: nil, mean: 0) }
        let scale = analysisWidth / CGFloat(source.width)
        let analysisSize = CGSize(width: analysisWidth, height: (CGFloat(source.height) * scale).rounded())
        guard let small = redraw(source, size: analysisSize) else { return PosterMask(image: nil, mean: 0) }
        let mean = meanLuminance(of: small)

        let handler = VNImageRequestHandler(cgImage: small)
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let text = VNDetectTextRectanglesRequest()
        let people = VNGeneratePersonSegmentationRequest()
        people.qualityLevel = .accurate
        people.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        try? handler.perform([foreground, faces, text, people, saliency])

        let width = Int(maskSize.width), height = Int(maskSize.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return PosterMask(image: nil, mean: mean) }
        let bounds = CGRect(origin: .zero, size: maskSize)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(bounds)
        context.interpolationQuality = .medium

        if let observation = foreground.results?.first {
            let instances = largeInstances(of: observation)
            if !instances.isEmpty,
               let buffer = try? observation.generateScaledMaskForImage(forInstances: instances, from: handler),
               let maskImage = cgImage(from: buffer) {
                context.draw(maskImage, in: bounds)
            }
        }

        context.setBlendMode(.lighten)
        if let buffer = people.results?.first?.pixelBuffer, let personImage = cgImage(from: buffer) {
            context.draw(personImage, in: bounds)
        }
        if let found = coverage(of: context, count: width * height), found < coverageRange.lowerBound,
           let buffer = saliency.results?.first?.pixelBuffer, let heatImage = cgImage(from: buffer) {
            context.draw(heatImage, in: bounds)
        }
        context.setBlendMode(.normal)

        if let found = coverage(of: context, count: width * height), found > coverageRange.upperBound {
            context.setFillColor(gray: 0, alpha: backgroundFloor)
            context.fill(bounds)
        }

        let boxes = (faces.results ?? []).map { $0.boundingBox.insetBy(dx: -$0.boundingBox.width * 0.25,
                                                                       dy: -$0.boundingBox.height * 0.25) }
            + (text.results ?? []).map(\.boundingBox)
        context.setFillColor(gray: 1, alpha: 1)
        for box in boxes {
            context.fillEllipse(in: CGRect(x: box.minX * maskSize.width, y: box.minY * maskSize.height,
                                           width: box.width * maskSize.width, height: box.height * maskSize.height))
        }

        if let background = backgroundLuminance(of: small, mask: context, size: maskSize) {
            let muted = darkBackgroundShare * (1 - smoothstep(0.12, 0.22, background))
            if muted > 0 {
                context.setFillColor(gray: 0, alpha: muted)
                context.fill(bounds)
            }
        }

        guard let raw = context.makeImage() else { return PosterMask(image: nil, mean: mean) }
        return PosterMask(image: feathered(raw, sigma: 2.5).map(UIImage.init(cgImage:)), mean: mean)
    }

    private nonisolated static func meanLuminance(of image: CGImage) -> Float {
        let width = 32, height = 48
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0.45 }
        return Float(pixels.reduce(0) { $0 + Int($1) }) / Float(width * height * 255)
    }

    private nonisolated static func backgroundLuminance(of image: CGImage, mask: CGContext, size: CGSize) -> CGFloat? {
        let width = Int(size.width), height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(origin: .zero, size: size))
            return true
        }
        guard drawn, let data = mask.data else { return nil }
        let protected = data.assumingMemoryBound(to: UInt8.self)
        var sum: CGFloat = 0, weight: CGFloat = 0
        for i in 0..<(width * height) {
            let open = 1 - CGFloat(protected[i]) / 255
            sum += CGFloat(pixels[i]) / 255 * open
            weight += open
        }
        return weight > 0.02 * CGFloat(width * height) ? sum / weight : 0
    }

    private nonisolated static func smoothstep(_ low: CGFloat, _ high: CGFloat, _ value: CGFloat) -> CGFloat {
        let t = min(max((value - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private nonisolated static func largeInstances(of observation: VNInstanceMaskObservation) -> IndexSet {
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return observation.allInstances }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var counts = [Int: Int]()
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width where row[x] != 0 { counts[Int(row[x]), default: 0] += 1 }
        }
        let total = Double(width * height)
        return IndexSet(observation.allInstances.filter { Double(counts[$0] ?? 0) / total >= minimumInstanceShare })
    }

    private nonisolated static func coverage(of context: CGContext, count: Int) -> Double? {
        guard let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var total = 0
        for i in 0..<count { total += Int(pixels[i]) }
        return Double(total) / Double(count * 255)
    }

    private nonisolated static func feathered(_ image: CGImage, sigma: Double) -> CGImage? {
        let input = CIImage(cgImage: image)
        let grown = input.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 1])
        let soft = grown.applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        return CIContext().createCGImage(soft, from: input.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
    }

    private nonisolated static func redraw(_ image: CGImage, size: CGSize) -> CGImage? {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    private nonisolated static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(image, from: image.extent)
    }
}
