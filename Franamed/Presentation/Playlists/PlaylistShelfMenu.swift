//
//  PlaylistShelfMenu.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.10.2026.
//

import SwiftUI
import UIKit

struct PlaylistMenuAction {
    let title: String
    let systemImage: String
    let handler: () -> Void
}

struct PlaylistShelfMenu: UIViewRepresentable {
    let title: String
    let preview: AnyView
    let actions: [PlaylistMenuAction]
    let onTap: () -> Void
    let onLift: (Bool) -> Void

    func makeUIView(context: Context) -> Control {
        Control()
    }

    func updateUIView(_ control: Control, context: Context) {
        control.preview = preview
        control.actions = actions
        control.onTap = onTap
        control.onLift = onLift
        control.accessibilityLabel = title
    }

    final class Control: UIControl {
        var preview = AnyView(EmptyView())
        var actions: [PlaylistMenuAction] = []
        var onTap: (() -> Void)?
        var onLift: ((Bool) -> Void)?

        private static weak var menuOwner: Control?

        private var previewHost: UIHostingController<AnyView>?
        private var isLifted = false
        private var isMenuShown = false
        private var isPressing = false {
            didSet { updateLift() }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isContextMenuInteractionEnabled = true
            isAccessibilityElement = true
            accessibilityTraits = .button
            addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
            addGestureRecognizer(PressRecognizer { [weak self] in self?.isPressing = $0 })
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            point.y >= PlaylistFolderCover.restTop(width: bounds.width) && super.point(inside: point, with: event)
        }

        override var isHighlighted: Bool {
            didSet { updateLift() }
        }

        private func updateLift() {
            let isBlocked = Self.menuOwner.map { $0 !== self } ?? false
            let isUp = isMenuShown || (!isBlocked && (isPressing || isHighlighted))
            guard isLifted != isUp else { return }
            isLifted = isUp
            onLift?(isUp)
        }

        // MARK: Menu

        override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                             configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            isMenuShown = true
            Self.menuOwner = self
            updateLift()
            let actions = actions
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                UIMenu(children: actions.map { action in
                    UIAction(title: action.title, image: UIImage(systemName: action.systemImage)) { _ in
                        Haptics.shared.play(.menuSelect)
                        action.handler()
                    }
                })
            }
        }

        override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                             configuration: UIContextMenuConfiguration,
                                             highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            targetedPreview()
        }

        override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                             configuration: UIContextMenuConfiguration,
                                             dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            targetedPreview()
        }

        override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                             willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                             animator: (any UIContextMenuInteractionAnimating)?) {
            super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
            Haptics.shared.play(.menu)
        }

        override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                             willEndFor configuration: UIContextMenuConfiguration,
                                             animator: (any UIContextMenuInteractionAnimating)?) {
            super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
            isMenuShown = false
            if Self.menuOwner === self { Self.menuOwner = nil }
            updateLift()
            animator?.addCompletion { [weak self] in self?.previewHost = nil }
        }

        private func targetedPreview() -> UITargetedPreview {
            let host = previewHost ?? UIHostingController(rootView: preview)
            previewHost = host
            host.view.backgroundColor = .clear
            host.view.frame = bounds
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.shadowPath = UIBezierPath()
            let target = UIPreviewTarget(container: self, center: CGPoint(x: bounds.midX, y: bounds.midY))
            return UITargetedPreview(view: host.view, parameters: parameters, target: target)
        }
    }
}

private final class PressRecognizer: UIGestureRecognizer {
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onChange(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        onChange(false)
    }
}
