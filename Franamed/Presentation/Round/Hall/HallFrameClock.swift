//
//  HallFrameClock.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 08.10.2026.
//

import QuartzCore

final class HallFrameClock: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    typealias Render = @Sendable (CAMetalDrawable, CFTimeInterval) -> Bool

    nonisolated(unsafe) private static let runLoop: RunLoop = {
        let thread = HallClockThread()
        thread.qualityOfService = .userInteractive
        thread.start()
        thread.ready.wait()
        return thread.loop
    }()

    private let lock = NSLock()
    private let render: Render
    private var link: CAMetalDisplayLink?
    private var needsFrame = true
    private var isAnimating = false

    init(layer: CAMetalLayer, render: @escaping Render) {
        self.render = render
        super.init()
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.preferredFrameLatency = 1
        link.delegate = self
        link.add(to: Self.runLoop, forMode: .default)
        self.link = link
    }

    func setNeedsFrame() {
        let link = lock.withLock {
            needsFrame = true
            return self.link
        }
        link?.isPaused = false
    }

    func invalidate() {
        let link = lock.withLock {
            defer { self.link = nil }
            return self.link
        }
        link?.invalidate()
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let wanted = lock.withLock {
            let wanted = needsFrame || isAnimating
            needsFrame = false
            return wanted
        }
        let animating = wanted && render(update.drawable, update.targetPresentationTimestamp)
        lock.withLock {
            isAnimating = animating
            if !animating && !needsFrame { link.isPaused = true }
        }
    }
}

private final class HallClockThread: Thread, @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private(set) var loop: RunLoop!

    override func main() {
        loop = RunLoop.current
        loop.add(NSMachPort(), forMode: .default)
        ready.signal()
        while true {
            loop.run(mode: .default, before: .distantFuture)
        }
    }
}
