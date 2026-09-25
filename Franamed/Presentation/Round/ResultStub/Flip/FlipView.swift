//
//  FlipView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.09.2026.
//

import SwiftUI
import UIKit

struct FlipView<Front: View, Back: View>: View {
    let size: CGSize
    let contentID: AnyHashable
    let menuItems: [FlipMenuItem]
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back

    @StateObject private var engine = FlipEngine()
    @StateObject private var faces = FlipFaces()
    @State private var isMenuActive = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DebugSettings.straightEdgeKey) private var usesStraightEdges = false

    var body: some View {
        let edgeStyle = TicketEdgeStyle(usesStraightEdges: usesStraightEdges)

        ZStack {
            FlipCanvas(engine: engine, faces: faces, size: size, edgeStyle: edgeStyle)
                .opacity(isMenuActive ? 0 : 1)
            FlipInteractionView(
                engine: engine,
                size: size,
                frontImage: faces.frontImage,
                backImage: faces.backImage,
                edgeStyle: edgeStyle,
                menuItems: menuItems,
                onMenuActiveChange: { isMenuActive = $0 }
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
        .task(id: contentID) {
            faces.capture(front: front(), back: back(), scale: displayScale)
        }
    }
}

private struct FlipInteractionView: UIViewRepresentable {
    let engine: FlipEngine
    let size: CGSize
    let frontImage: UIImage?
    let backImage: UIImage?
    let edgeStyle: TicketEdgeStyle
    let menuItems: [FlipMenuItem]
    let onMenuActiveChange: (Bool) -> Void

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
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
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
        coordinator.onMenuActiveChange = onMenuActiveChange
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
        var engine: FlipEngine?
        var size: CGSize = .zero
        var frontImage: UIImage?
        var backImage: UIImage?
        var edgeStyle: TicketEdgeStyle = .scalloped
        var menuItems: [FlipMenuItem] = []
        var onMenuActiveChange: (Bool) -> Void = { _ in }

        private static let highlightTimeout: TimeInterval = 1.0

        private var isMenuActive = false
        private var didDisplayMenu = false
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

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard !isMenuActive, !menuItems.isEmpty, engine?.isApproachingRest == true,
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
            beginMenu()
            return preview(in: interaction.view)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configuration: UIContextMenuConfiguration,
                                    dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            preview(in: interaction.view)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                    animator: (any UIContextMenuInteractionAnimating)?) {
            didDisplayMenu = true
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
            onMenuActiveChange(true)
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.highlightTimeout) { [weak self] in
                guard let self, self.generation == current, self.isMenuActive, !self.didDisplayMenu else { return }
                self.endMenu()
            }
        }

        private func endMenu() {
            isMenuActive = false
            didDisplayMenu = false
            onMenuActiveChange(false)
        }

        private var currentImage: UIImage? {
            (engine?.isFrontVisible ?? true) ? frontImage : backImage
        }

        private func preview(in container: UIView?) -> UITargetedPreview? {
            guard let container, let image = currentImage else { return nil }
            let isFront = engine?.isFrontVisible ?? true

            let imageView = UIImageView(image: image)
            imageView.frame = CGRect(origin: .zero, size: size)

            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            let outline = ResultStubShape(edgeStyle: edgeStyle, mirrored: isFront)
                .path(in: CGRect(origin: .zero, size: size))
            parameters.visiblePath = UIBezierPath(cgPath: outline.cgPath)

            let target = UIPreviewTarget(container: container,
                                         center: CGPoint(x: container.bounds.midX, y: container.bounds.midY))
            return UITargetedPreview(view: imageView, parameters: parameters, target: target)
        }
    }
}
