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
    var frameMidX: CGFloat = 0
    let onToggleOrientation: () -> Void
    let onTapPrevious: () -> Void
    let onTapNext: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let coordinator = context.coordinator
        let frameTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.frameTapped(_:)))
        let phoneTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.phoneTapped(_:)))
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
        let rotation = UIRotationGestureRecognizer(target: coordinator, action: #selector(Coordinator.rotated(_:)))
        coordinator.frameTap = frameTap
        coordinator.phoneTap = phoneTap
        coordinator.pinch = pinch
        coordinator.rotation = rotation
        for gesture in [frameTap, phoneTap, pan, pinch, rotation] as [UIGestureRecognizer] {
            gesture.delegate = coordinator
            view.addGestureRecognizer(gesture)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.surface = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(surface: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var surface: HallPhoneSurface
        weak var frameTap: UITapGestureRecognizer?
        weak var phoneTap: UITapGestureRecognizer?
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
            view.convert(CGPoint(x: frameMidX(in: view), y: surface.frameTop + surface.frameHeight * 0.8), to: nil)
        }

        private func frameMidX(in view: UIView) -> CGFloat {
            surface.frameMidX > 0 ? surface.frameMidX : view.bounds.midX
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            let onPhone = phone.contains(touch.location(in: nil))
            if gesture === frameTap {
                guard let view = gesture.view, !onPhone else { return false }
                let y = touch.location(in: view).y
                return (surface.frameTop..<surface.frameTop + surface.frameHeight).contains(y)
            }
            if gesture === phoneTap {
                return onPhone || (phone.isHeld && phone.isOnRest(touch.location(in: nil)))
            }
            if gesture is UIPanGestureRecognizer { return onPhone }
            if gesture === pinch || gesture === rotation { return phone.isHeld }
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
            if gesture.location(in: view).x < frameMidX(in: view) { surface.onTapPrevious() } else { surface.onTapNext() }
        }

        @objc func phoneTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: nil)
            if !phone.isHeld {
                phone.raise(to: home(in: view))
            } else if !phone.contains(location), phone.isOnRest(location) {
                phone.lower()
            } else if phone.isShowingApp {
                if phone.contains(location) { phone.dismissApp() }
            } else {
                switch phone.spot(at: location) {
                case .finder: phone.cycleZoom()
                case .turn: surface.onToggleOrientation()
                case .body, nil: break
                }
            }
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
            decide()
            if twoFingers == .zoom { phone.pinch(gesture.scale, ended: !isActive) }
            if !isActive { finishTwoFingers() }
        }

        @objc func rotated(_ gesture: UIRotationGestureRecognizer) {
            lastRotation = gesture.rotation
            let isActive = gesture.state == .began || gesture.state == .changed
            decide()
            if isActive, twoFingers == .twist { phone.twist(gesture.rotation) }
            if !isActive {
                if twoFingers == .twist, phone.endTwist() { surface.onToggleOrientation() }
                finishTwoFingers()
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
