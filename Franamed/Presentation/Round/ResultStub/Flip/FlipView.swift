//
//  FlipView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.09.2026.
//

import Metal
import SwiftUI
import UIKit

struct FlipView<Front: View, Back: View>: View {
    let size: CGSize
    let contentID: AnyHashable
    let menuItems: [FlipMenuItem]
    var snapshotter: FlipSnapshotter?
    var allowsRotation = true
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back
    var onFrontVisibleChange: (Bool) -> Void = { _ in }

    @StateObject private var engine = FlipEngine()
    @StateObject private var faces = FlipFaces()

    @Environment(\.displayScale) private var displayScale
    @Environment(\.flipLighting) private var lighting
    @Environment(\.flipRecordingLighting) private var recordingLighting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false

    var body: some View {
        let edgeStyle = TicketEdgeStyle(hasScallops: hasScallops)

        ZStack {
            Group {
                if let recordingLighting {
                    FlipCanvas(engine: engine, faces: faces, size: size, edgeStyle: edgeStyle,
                               lighting: recordingLighting, isProtected: false, providesSnapshot: false)
                }
                FlipCanvas(engine: engine, faces: faces, size: size, edgeStyle: edgeStyle,
                           lighting: lighting, isProtected: recordingLighting != nil)
            }
            FlipInteractionView(
                engine: engine,
                size: size,
                frontImage: faces.frontImage,
                backImage: faces.backImage,
                edgeStyle: edgeStyle,
                menuItems: menuItems,
                allowsRotation: allowsRotation
            )
        }
        .frame(width: size.width, height: size.height)
        .accessibilityRepresentation {
            if engine.isFrontVisible { front() } else { back() }
        }
        .accessibilityAction(named: "Перевернуть") { engine.flip(towardsTrailing: true) }
        .accessibilityActions {
            ForEach(menuItems) { item in
                Button(item.title, systemImage: item.systemImage, action: item.action)
            }
        }
        .onChange(of: reduceMotion, initial: true) { _, new in engine.settlesInstantly = new }
        .onChange(of: engine.isFrontVisible) { _, isFront in onFrontVisibleChange(isFront) }
        .onAppear {
            snapshotter?.engine = engine
            snapshotter?.scale = displayScale
        }
        .task(id: contentID) {
            faces.capture(front: front(), back: back(), scale: displayScale)
        }
    }
}

@MainActor
final class FlipSnapshotter {
    weak var engine: FlipEngine?
    var scale: CGFloat = 3

    func render(front: some View) -> UIImage? {
        guard let image = TicketSnapshot.image(of: front, scale: scale) else { return nil }
        return engine?.plainSnapshot?(image)
    }

    func hostController() -> UIViewController? {
        engine?.hostController?()
    }

    func flightRenderer() -> FlipFlight? {
        engine?.flightRenderer?()
    }

    func frameInWindow() -> CGRect? {
        engine?.frameInWindow?()
    }

    func faceTexture(front: some View) -> MTLTexture? {
        TicketSnapshot.texture(of: front, scale: scale)
    }
}

private struct FlipInteractionView: UIViewRepresentable {
    let engine: FlipEngine
    let size: CGSize
    let frontImage: UIImage?
    let backImage: UIImage?
    let edgeStyle: TicketEdgeStyle
    let menuItems: [FlipMenuItem]
    let allowsRotation: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = FlipPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        pan.onTouchesBegan = { [weak coordinator = context.coordinator] in coordinator?.engine?.resetTouches() }
        pan.onTouchSample = { [weak coordinator = context.coordinator] time, x in
            coordinator?.engine?.recordTouch(time: time, x: x)
        }
        pan.isEnabled = allowsRotation
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.delegate = context.coordinator
        tap.isEnabled = allowsRotation
        view.addGestureRecognizer(tap)

        let menu = UIContextMenuInteraction(delegate: context.coordinator)
        view.addInteraction(menu)
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { [weak coordinator = context.coordinator, weak menu] _, update in
                coordinator?.hingeChanged(to: update.hinge?.status.rawValue, menu: menu)
            })
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.engine = engine
        coordinator.size = size
        coordinator.frontImage = frontImage
        coordinator.backImage = backImage
        coordinator.edgeStyle = edgeStyle
        coordinator.menuItems = menuItems
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
        var engine: FlipEngine?
        var size: CGSize = .zero
        var frontImage: UIImage?
        var backImage: UIImage?
        var edgeStyle: TicketEdgeStyle = .scalloped
        var menuItems: [FlipMenuItem] = []

        private static let highlightTimeout: TimeInterval = 1.0
        private static let lightFade: TimeInterval = 0.3

        private var isMenuActive = false
        private var didDisplayMenu = false
        private var hingeStatus: Int?
        private weak var litView: UIView?
        private var previewView: UIView?
        private var tearPreview: (plain: UIImage, lit: UIImage?)?
        private var generation = 0

        // MARK: Rotation

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let engine, let view = recognizer.view else { return }
            switch recognizer.state {
            case .began:
                engine.beginDrag()
                engine.drag(translation: recognizer.translation(in: view).x, width: size.width)
            case .changed:
                engine.drag(translation: recognizer.translation(in: view).x, width: size.width)
            case .ended:
                engine.endDrag(releaseVelocity: recognizer.velocity(in: view).x, width: size.width)
            case .cancelled, .failed:
                engine.endDrag()
            default:
                break
            }
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard let engine, let view = recognizer.view else { return }
            engine.tapEdge(at: recognizer.location(in: view).x, width: size.width)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            !isMenuActive
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UIPanGestureRecognizer,
                  let view = gestureRecognizer.view, let otherView = other.view,
                  otherView !== view else { return false }
            return view.isDescendant(of: otherView)
        }

        // MARK: Menu

        func hingeChanged(to status: Int?, menu: UIContextMenuInteraction?) {
            defer { hingeStatus = status }
            guard hingeStatus != nil, status != hingeStatus, isMenuActive else { return }
            menu?.dismissMenu()
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard !isMenuActive, !menuItems.isEmpty, engine?.isApproachingRest == true, engine?.isTearHealing?() != true,
                  currentImage != nil else { return nil }
            let items = menuItems
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                UIMenu(children: items.map { item in
                    UIAction(title: item.title, image: UIImage(systemName: item.systemImage)) { _ in
                        item.action()
                    }
                })
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configuration: UIContextMenuConfiguration,
                                    highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            if engine?.isAnimating == true { engine?.settleImmediately() }
            let lit = engine?.litSnapshot?()
            tearPreview = engine?.tearSnapshot?()
            beginMenu()
            previewView = makePreviewView(lit: lit)
            return targetedPreview(in: interaction.view)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configuration: UIContextMenuConfiguration,
                                    dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            if previewView == nil { tearPreview = engine?.tearSnapshot?() }
            previewView = previewView ?? makePreviewView(lit: engine?.litSnapshot?())
            let preview = targetedPreview(in: interaction.view)
            if let litView {
                UIView.animate(withDuration: Self.lightFade, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                    litView.alpha = 1
                }
            }
            return preview
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                    animator: (any UIContextMenuInteractionAnimating)?) {
            didDisplayMenu = true
            guard let litView else { return }
            if let animator {
                animator.addAnimations { litView.alpha = 0 }
            } else {
                litView.alpha = 0
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willEndFor configuration: UIContextMenuConfiguration,
                                    animator: (any UIContextMenuInteractionAnimating)?) {
            guard let animator else { endMenu(); return }
            let current = generation
            animator.addCompletion { [weak self] in
                guard let self, self.generation == current else { return }
                self.endMenu()
            }
        }

        private func beginMenu() {
            generation += 1
            isMenuActive = true
            didDisplayMenu = false
            let current = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == current, self.isMenuActive else { return }
                self.engine?.onCanvasHidden?(true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.highlightTimeout) { [weak self] in
                guard let self, self.generation == current, self.isMenuActive, !self.didDisplayMenu else { return }
                self.endMenu()
            }
        }

        private func endMenu() {
            previewView = nil
            isMenuActive = false
            didDisplayMenu = false
            engine?.onCanvasHidden?(false)
        }

        private var currentImage: UIImage? {
            (engine?.isFrontVisible ?? true) ? frontImage : backImage
        }

        private func makePreviewView(lit: UIImage?) -> UIView? {
            if let tearPreview {
                let margin = FlipRenderer.Coordinator.tearMargin(forStubWidth: size.width)
                return makePreviewView(image: tearPreview.plain, lit: tearPreview.lit,
                                       frame: CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin))
            }
            guard let image = currentImage else { return nil }
            return makePreviewView(image: image, lit: lit, frame: CGRect(origin: .zero, size: size))
        }

        private func makePreviewView(image: UIImage, lit: UIImage?, frame: CGRect) -> UIView {
            let previewView = UIView(frame: frame)
            previewView.addSubview(UIImageView(image: image))
            litView = lit.map { lit in
                let view = UIImageView(image: lit)
                previewView.addSubview(view)
                return view
            }
            for view in previewView.subviews { view.frame = previewView.bounds }
            return previewView
        }

        private func targetedPreview(in container: UIView?) -> UITargetedPreview? {
            guard let container, let previewView else { return nil }
            let isFront = engine?.isFrontVisible ?? true

            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            if tearPreview != nil {
                parameters.visiblePath = UIBezierPath(rect: previewView.bounds)
            } else {
                let outline = ResultStubShape(edgeStyle: edgeStyle, mirrored: isFront)
                    .path(in: CGRect(origin: .zero, size: size))
                parameters.visiblePath = UIBezierPath(cgPath: outline.cgPath)
            }

            let target = UIPreviewTarget(container: container,
                                         center: CGPoint(x: container.bounds.midX, y: container.bounds.midY))
            return UITargetedPreview(view: previewView, parameters: parameters, target: target)
        }
    }
}
