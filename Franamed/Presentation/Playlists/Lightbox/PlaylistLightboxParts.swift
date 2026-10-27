//
//  PlaylistLightboxParts.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import SwiftUI
import UIKit

@MainActor
final class PlaylistSnapshotters {
    private var byKey: [String: FlipSnapshotter] = [:]

    subscript(key: String) -> FlipSnapshotter {
        if let snapshotter = byKey[key] { return snapshotter }
        let snapshotter = FlipSnapshotter()
        byKey[key] = snapshotter
        return snapshotter
    }
}

struct PlaylistLightboxBackdrop: View, Animatable {
    var progress: CGFloat
    let dim: Double

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack {
            PlaylistBlurView(fraction: progress)
            Color.black.opacity(dim * progress)
        }
    }
}

private struct PlaylistBlurView: UIViewRepresentable {
    let fraction: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: nil)
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
            view.effect = UIBlurEffect(style: .systemMaterialDark)
        }
        animator.pausesOnCompletion = true
        context.coordinator.animator = animator
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        context.coordinator.animator?.fractionComplete = min(max(fraction, 0), 1)
    }

    static func dismantleUIView(_ view: UIVisualEffectView, coordinator: Coordinator) {
        coordinator.animator?.stopAnimation(true)
    }

    final class Coordinator {
        var animator: UIViewPropertyAnimator?
    }
}

struct PlaylistLightboxPageMotion: ViewModifier {
    let flight: CGFloat
    let isFocused: Bool
    let source: CGRect?
    let target: CGRect
    let width: CGFloat
    let drag: CGFloat
    let shrinkDistance: CGFloat
    let maxShrink: CGFloat
    let neighborShift: CGFloat

    func body(content: Content) -> some View {
        content
            .modifier(PlaylistDragEffect(drag: isFocused ? drag : 0, shrinkDistance: shrinkDistance,
                                         maxShrink: maxShrink))
            .modifier(PlaylistFlightEffect(progress: isFocused ? flight : 1,
                                           offset: source.map { CGSize(width: $0.midX - target.midX,
                                                                       height: $0.midY - target.midY) } ?? .zero,
                                           scale: source.map { $0.width / width } ?? 1))
            .offset(x: neighborShift * (1 - flight))
            .opacity(isFocused && source != nil ? 1 : flight)
    }
}

private struct PlaylistDragEffect: GeometryEffect {
    var drag: CGFloat
    let shrinkDistance: CGFloat
    let maxShrink: CGFloat

    var animatableData: CGFloat {
        get { drag }
        set { drag = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let scale = 1 - min(abs(drag) / shrinkDistance, maxShrink)
        let transform = CGAffineTransform.identity
            .translatedBy(x: size.width / 2, y: size.height / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -size.width / 2, y: -size.height / 2 + drag)
        return ProjectionTransform(transform)
    }
}

private struct PlaylistFlightEffect: GeometryEffect {
    var progress: CGFloat
    let offset: CGSize
    let scale: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let rest = 1 - progress
        let factor = 1 + (scale - 1) * rest
        let transform = CGAffineTransform.identity
            .translatedBy(x: size.width / 2 + offset.width * rest, y: size.height / 2 + offset.height * rest)
            .scaledBy(x: factor, y: factor)
            .translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(transform)
    }
}

struct PlaylistLightboxPan: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).y
        switch recognizer.state {
        case .began, .changed:
            onChange(translation)
        case .ended:
            onEnd(translation, recognizer.velocity(in: recognizer.view).y)
        case .cancelled, .failed:
            onEnd(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let view = gestureRecognizer.view, let otherView = other.view, otherView !== view else { return false }
            return view.isDescendant(of: otherView)
        }
    }
}

final class PlaylistScrollFreezer {
    fileprivate weak var scrollView: UIScrollView?
    private(set) var isAligned = true

    @MainActor
    func cancelTouch() -> Bool {
        guard let pan = scrollView?.panGestureRecognizer, pan.state == .began || pan.state == .changed else { return false }
        stop()
        return true
    }

    @MainActor
    func stop() {
        guard let scrollView else { return }
        isAligned = false
        scrollView.panGestureRecognizer.isEnabled = false
        scrollView.panGestureRecognizer.isEnabled = true
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    }

    func align() {
        isAligned = true
    }
}

struct PlaylistLightboxScrollBehavior: ScrollTargetBehavior {
    let freezer: PlaylistScrollFreezer
    private let aligned = ViewAlignedScrollTargetBehavior(limitBehavior: .alwaysByOne)

    init(freezer: PlaylistScrollFreezer) {
        self.freezer = freezer
    }

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard freezer.isAligned else { return }
        aligned.updateTarget(&target, context: context)
    }

    func properties(context: PropertiesContext) -> Properties {
        aligned.properties(context: context)
    }

    func _updateEnvironment(_ env: inout EnvironmentValues, context: _ScrollTargetBehaviorEnvironmentContext) {
        aligned._updateEnvironment(&env, context: context)
    }

    static func _makeInputs(_ behavior: _GraphValue<Self>, inputs: inout _ViewInputs) {
        ViewAlignedScrollTargetBehavior._makeInputs(behavior[\.aligned], inputs: &inputs)
    }
}

struct PlaylistScrollFreezerAnchor: UIViewRepresentable {
    let freezer: PlaylistScrollFreezer

    func makeUIView(context: Context) -> AnchorView { AnchorView(freezer: freezer) }

    func updateUIView(_ view: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        private let freezer: PlaylistScrollFreezer

        init(freezer: PlaylistScrollFreezer) {
            self.freezer = freezer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var ancestor = superview
            while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
            freezer.scrollView = ancestor as? UIScrollView
        }
    }
}
