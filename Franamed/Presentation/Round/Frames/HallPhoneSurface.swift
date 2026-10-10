//
//  HallPhoneSurface.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 08.10.2026.
//

import SwiftUI
import UIKit

struct HallPhoneSurface: UIViewRepresentable {
    let phone: HallPhone
    var frameTop: CGFloat = 0
    let frameHeight: CGFloat
    var isNewGestures = false
    let onToggleOrientation: () -> Void
    let onTapPrevious: () -> Void
    let onTapNext: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let coordinator = context.coordinator
        let frameTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.frameTapped(_:)))
        let phoneTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.phoneTapped(_:)))
        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.phoneDoubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        phoneTap.require(toFail: doubleTap)
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
        let rotation = UIRotationGestureRecognizer(target: coordinator, action: #selector(Coordinator.rotated(_:)))
        coordinator.frameTap = frameTap
        coordinator.phoneTap = phoneTap
        coordinator.doubleTap = doubleTap
        coordinator.pinch = pinch
        coordinator.rotation = rotation
        for gesture in [frameTap, phoneTap, doubleTap, pan, pinch, rotation] as [UIGestureRecognizer] {
            gesture.delegate = coordinator
            view.addGestureRecognizer(gesture)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.surface = self
        context.coordinator.doubleTap?.isEnabled = !isNewGestures
    }

    func makeCoordinator() -> Coordinator { Coordinator(surface: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var surface: HallPhoneSurface
        weak var frameTap: UITapGestureRecognizer?
        weak var phoneTap: UITapGestureRecognizer?
        weak var doubleTap: UITapGestureRecognizer?
        weak var pinch: UIPinchGestureRecognizer?
        weak var rotation: UIRotationGestureRecognizer?
        private var twoFingers = TwoFingers.undecided
        private var lastScale: CGFloat = 1
        private var lastRotation: CGFloat = 0

        private enum TwoFingers { case undecided, zoom, twist }
        private static let twistStart: CGFloat = 0.2
        private static let zoomStart: CGFloat = 0.08

        init(surface: HallPhoneSurface) {
            self.surface = surface
        }

        private var phone: HallPhone { surface.phone }

        private func home(in view: UIView) -> CGPoint {
            view.convert(CGPoint(x: view.bounds.midX, y: surface.frameTop + surface.frameHeight * 0.8), to: nil)
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let onPhone = phone.contains(touch.location(in: nil))
            if gesture === frameTap {
                guard let view = gesture.view, !onPhone else { return false }
                let y = touch.location(in: view).y
                return (surface.frameTop..<surface.frameTop + surface.frameHeight).contains(y)
            }
            if gesture === phoneTap {
                return onPhone || (surface.isNewGestures && phone.isHeld && phone.isOnRest(touch.location(in: nil)))
            }
            if gesture is UIPanGestureRecognizer { return onPhone }
            if surface.isNewGestures, gesture === pinch || gesture === rotation { return phone.isHeld }
            return onPhone && phone.isHeld
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let continuous: (UIGestureRecognizer) -> Bool = {
                $0 is UIPanGestureRecognizer || $0 is UIPinchGestureRecognizer || $0 is UIRotationGestureRecognizer
            }
            return continuous(gesture) && continuous(other)
        }

        @objc func frameTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            if gesture.location(in: view).x < view.bounds.midX { surface.onTapPrevious() } else { surface.onTapNext() }
        }

        @objc func phoneTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: nil)
            if !phone.isHeld {
                phone.raise(to: home(in: view))
            } else if !surface.isNewGestures {
                phone.cycleZoom()
            } else if !phone.contains(location), phone.isOnRest(location) {
                phone.lower()
            } else {
                switch phone.spot(at: location) {
                case .finder: phone.cycleZoom()
                case .turn: surface.onToggleOrientation()
                case .body, nil: break
                }
            }
        }

        @objc func phoneDoubleTapped(_ gesture: UITapGestureRecognizer) {
            surface.onToggleOrientation()
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                if !phone.isHeld { phone.raise(grabbing: gesture.location(in: nil)) }
                phone.drag(by: gesture.translation(in: nil))
            case .changed:
                phone.drag(by: gesture.translation(in: nil))
            default:
                phone.endDrag(velocity: gesture.velocity(in: nil))
            }
        }

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            lastScale = gesture.scale
            let isActive = gesture.state == .began || gesture.state == .changed
            if surface.isNewGestures {
                decide()
                if twoFingers == .zoom { phone.pinch(gesture.scale, ended: !isActive) }
                if !isActive { finishTwoFingers() }
            } else {
                phone.pinch(gesture.scale, ended: !isActive)
            }
        }

        @objc func rotated(_ gesture: UIRotationGestureRecognizer) {
            lastRotation = gesture.rotation
            let isActive = gesture.state == .began || gesture.state == .changed
            if surface.isNewGestures {
                decide()
                if isActive, twoFingers == .twist { phone.twist(gesture.rotation) }
                if !isActive {
                    if twoFingers == .twist, phone.endTwist() { surface.onToggleOrientation() }
                    finishTwoFingers()
                }
            } else if isActive {
                phone.twist(gesture.rotation)
            } else if phone.endTwist() {
                surface.onToggleOrientation()
            }
        }

        private func decide() {
            guard twoFingers == .undecided else { return }
            if abs(lastRotation) > Self.twistStart {
                twoFingers = .twist
            } else if abs(log(max(lastScale, 0.01))) > Self.zoomStart {
                twoFingers = .zoom
            }
        }

        private func finishTwoFingers() {
            let active: (UIGestureRecognizer?) -> Bool = { $0?.state == .began || $0?.state == .changed }
            guard !active(pinch), !active(rotation) else { return }
            twoFingers = .undecided
            lastScale = 1
            lastRotation = 0
        }
    }
}
