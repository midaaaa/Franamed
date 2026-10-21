//
//  PlaylistFlightAnimator.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.10.2026.
//

import Combine
import SwiftUI
import UIKit

@MainActor
final class PlaylistFlightState: ObservableObject {
    nonisolated static let shelfSpace = "playlistShelf"

    @Published var flyingID: String?
    @Published var openID: String?
    let track = PlaylistPosterTrack()
    var folderFrames: [String: CGRect] = [:]
    var cellFrames: [String: CGRect] = [:]
    var headerFrames: [String: CGRect] = [:]
}

@MainActor
final class PlaylistPosterTrack: ObservableObject {
    static let idle = PlaylistPosterTrack()
    @Published var slots: [PlaylistPosterSlot]?
    @Published var isCopyShown = false
}

struct PlaylistFlightSample {
    let slots: [PlaylistPosterSlot]
    let isCopyShown: Bool
}

struct PlaylistFlightPlan {
    let images: [UIImage?]
    let folder: [PlaylistPosterSlot]
    let header: [PlaylistPosterSlot]
    let frontTop: CGFloat
}

final class PlaylistFlightAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPush: Bool
    private let plan: (UIView) -> PlaylistFlightPlan?
    private let onStart: ((() -> PlaylistFlightSample)?) -> Void
    private let onEnd: () -> Void
    private var animator: UIViewPropertyAnimator?
    private var isPrepared = false

    private static let pushDuration: TimeInterval = 0.6
    private static let popDuration: TimeInterval = 0.55
    static let handoffDuration: TimeInterval = 0.15
    private static let popContentFade = 0.3
    private static let popBackdropFade = 0.55
    static let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.4, y: 0),
                                                controlPoint2: CGPoint(x: 0.2, y: 1))

    init(isPush: Bool, plan: @escaping (UIView) -> PlaylistFlightPlan?,
         onStart: @escaping ((() -> PlaylistFlightSample)?) -> Void, onEnd: @escaping () -> Void) {
        self.isPush = isPush
        self.plan = plan
        self.onStart = onStart
        self.onEnd = onEnd
    }

    func transitionDuration(using context: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        isPush ? Self.pushDuration : Self.popDuration
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard isPush else {
            interruptibleAnimator(using: context).startAnimation()
            return
        }
        prepare(context)
        DispatchQueue.main.async {
            self.interruptibleAnimator(using: context).startAnimation()
        }
    }

    func interruptibleAnimator(using context: any UIViewControllerContextTransitioning) -> any UIViewImplicitlyAnimating {
        if let animator { return animator }
        prepare(context)
        let animator = makeAnimator(context)
        self.animator = animator
        return animator
    }

    private func prepare(_ context: any UIViewControllerContextTransitioning) {
        guard !isPrepared, let toVC = context.viewController(forKey: .to),
              let toView = context.view(forKey: .to) else { return }
        isPrepared = true
        toView.frame = context.finalFrame(for: toVC)
        if isPush {
            toView.alpha = 0
            context.containerView.addSubview(toView)
        } else {
            context.containerView.insertSubview(toView, at: 0)
        }
        toView.layoutIfNeeded()
    }

    private func makeAnimator(_ context: any UIViewControllerContextTransitioning) -> UIViewPropertyAnimator {
        let container = context.containerView
        let fromView = context.view(forKey: .from)
        let toView = context.view(forKey: .to)
        let isPush = isPush

        let backdrop = UIView(frame: container.bounds)
        backdrop.backgroundColor = .systemBackground
        backdrop.alpha = isPush ? 0 : 1
        if let detail = isPush ? toView : fromView {
            container.insertSubview(backdrop, belowSubview: detail)
        }

        let flight = plan(container).map { PlaylistFlightView(plan: $0, bounds: container.bounds, startsInFolder: isPush) }
        if let flight {
            container.addSubview(flight)
            onStart { flight.step() }
        } else {
            onStart(nil)
        }

        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: context), timingParameters: Self.timing)
        animator.addAnimations {
            if isPush {
                backdrop.alpha = 1
                toView?.alpha = 1
            } else {
                UIView.animateKeyframes(withDuration: 0, delay: 0) {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: Self.popContentFade) {
                        fromView?.alpha = 0
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: Self.popBackdropFade) {
                        backdrop.alpha = 0
                    }
                }
            }
            flight?.addKeyframes(isPush: isPush)
        }
        animator.addCompletion { [onEnd] position in
            let completed = position == .end
            fromView?.alpha = 1
            toView?.alpha = 1
            backdrop.removeFromSuperview()
            if !completed { toView?.removeFromSuperview() }
            context.completeTransition(completed)
            onEnd()
            UIView.animate(withDuration: Self.handoffDuration, delay: 0, options: .curveLinear) {
                flight?.alpha = 0
            } completion: { _ in
                flight?.removeFromSuperview()
            }
        }
        return animator
    }
}

// MARK: - Flight view

private final class PlaylistFlightView: UIView {
    private let plan: PlaylistFlightPlan
    private let cards: [UIView]
    private let images: [UIImageView]
    private let shadows: [UIView]
    private var hideStreak = 0

    private static let hideLag = 2
    private static let cornerClearance: CGFloat = 2
    private static let liftTime = 0.3
    private static let liftClearance: CGFloat = 8
    private static let liftDrift: CGFloat = 0.15

    init(plan: PlaylistFlightPlan, bounds: CGRect, startsInFolder: Bool) {
        self.plan = plan
        let count = min(plan.images.count, plan.folder.count, plan.header.count)
        images = plan.images.prefix(count).map { image in
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.backgroundColor = .tertiarySystemFill
            return view
        }
        shadows = images.map { _ in
            let shadow = UIView()
            shadow.backgroundColor = .black
            shadow.layer.shadowColor = UIColor.black.cgColor
            shadow.layer.shadowOpacity = 0.3
            shadow.layer.shadowRadius = 6
            shadow.layer.shadowOffset = CGSize(width: 0, height: 6)
            return shadow
        }
        cards = zip(images, shadows).map { image, shadow in
            let card = UIView()
            card.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
            card.addSubview(shadow)
            card.addSubview(image)
            return card
        }
        super.init(frame: bounds)
        isUserInteractionEnabled = false
        isHidden = startsInFolder
        cards.reversed().forEach(addSubview)
        if startsInFolder {
            place(plan.folder, radius: folderRadius, shadow: 0)
        } else {
            place(plan.header, radius: headerRadius, shadow: 1)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var headerRadius: CGFloat {
        PlaylistPosterFan.cornerRadius(posterWidth: plan.header.first?.size.width ?? 0)
    }

    private var folderRadius: CGFloat {
        PlaylistFolderCover.posterCornerRadius(posterWidth: plan.folder.first?.size.width ?? 0)
    }

    func addKeyframes(isPush: Bool) {
        let liftAt = isPush ? Self.liftTime : 1 - Self.liftTime
        let folderRadius = self.folderRadius
        let headerRadius = self.headerRadius
        let lifted = liftedSlots
        let liftedRadius = folderRadius + (headerRadius - folderRadius) * Self.liftDrift
        UIView.animateKeyframes(withDuration: 0, delay: 0, options: .calculationModeCubic) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: liftAt) {
                self.place(lifted, radius: liftedRadius, shadow: 0)
            }
            UIView.addKeyframe(withRelativeStartTime: liftAt, relativeDuration: 1 - liftAt) {
                if isPush {
                    self.place(self.plan.header, radius: headerRadius, shadow: 0)
                } else {
                    self.place(self.plan.folder, radius: folderRadius, shadow: 0)
                }
            }
        }
    }

    func step() -> PlaylistFlightSample {
        let slots = presentedSlots()
        if let main = slots.first, let lifted = liftedSlots.first {
            let window = convert(CGPoint(x: 0, y: plan.frontTop), to: nil).y
            let lowest = slots.map(\.boundingBox.maxY).max() ?? main.bottomCenter.y
            let isInFolder = main.size.width <= lifted.size.width + 0.5 && lowest > window - Self.cornerClearance
            hideStreak = isInFolder ? hideStreak + 1 : 0
            if !isInFolder {
                isHidden = false
            } else if hideStreak > Self.hideLag {
                isHidden = true
            }
            return PlaylistFlightSample(slots: slots, isCopyShown: !isInFolder)
        }
        return PlaylistFlightSample(slots: slots, isCopyShown: !isHidden)
    }

    private func presentedSlots() -> [PlaylistPosterSlot] {
        cards.map { card in
            let layer = card.layer.presentation() ?? card.layer
            let transform = layer.affineTransform()
            return PlaylistPosterSlot(bottomCenter: convert(layer.position, to: nil),
                                      size: layer.bounds.size,
                                      angle: atan2(transform.b, transform.a) * 180 / .pi)
        }
    }

    private var liftedSlots: [PlaylistPosterSlot] {
        zip(plan.folder, plan.header).map { folder, header in
            let drift = Self.liftDrift
            let width = folder.size.width + (header.size.width - folder.size.width) * drift
            return PlaylistPosterSlot(
                bottomCenter: CGPoint(x: folder.bottomCenter.x + (header.bottomCenter.x - folder.bottomCenter.x) * drift,
                                      y: plan.frontTop - Self.liftClearance),
                size: CGSize(width: width, height: width * 1.5),
                angle: folder.angle + (header.angle - folder.angle) * drift
            )
        }
    }

    private func place(_ slots: [PlaylistPosterSlot], radius: CGFloat, shadow: CGFloat) {
        for (index, card) in cards.enumerated() where index < slots.count {
            let slot = slots[index]
            card.bounds = CGRect(origin: .zero, size: slot.size)
            card.center = slot.bottomCenter
            card.transform = CGAffineTransform(rotationAngle: slot.angle * .pi / 180)
            images[index].frame = card.bounds
            images[index].layer.cornerRadius = radius
            shadows[index].frame = card.bounds
            shadows[index].layer.cornerRadius = radius
            shadows[index].alpha = shadow
        }
    }
}

extension View {
    func onGlobalFrameChange(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { action($0) }
    }

    func onShelfFrameChange(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PlaylistFlightState.shelfSpace)) } action: { action($0) }
    }
}
