//
//  ProtectedBox.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.09.2026.
//

import UIKit

final class ProtectedBox: UIView {

    private let field = UITextField()
    private let openHost = UIView()
    private let child: UIView

    private var protectedHost: UIView?

    var isProtected = false {
        didSet {
            guard oldValue != isProtected else { return }
            attachChild()
        }
    }

    init(child: UIView) {
        self.child = child
        super.init(frame: .zero)

        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        field.backgroundColor = .clear
        field.clipsToBounds = false
        addSubview(field)

        openHost.isUserInteractionEnabled = false
        addSubview(openHost)

        child.autoresizingMask = []
        openHost.addSubview(child)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, protectedHost == nil else { return }

        layoutIfNeeded()
        protectedHost = field.subviews.first {
            String(describing: type(of: $0)).contains("CanvasView")
        }

        if protectedHost == nil {
            NSLog("[Shield] не нашёл защищённый слой, содержимое осталось незащищённым")
        }

        protectedHost?.clipsToBounds = false
        attachChild()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        field.frame = bounds
        openHost.frame = bounds

        if let host = child.superview {
            child.frame = host.convert(bounds, from: self)
        }
    }

    private func attachChild() {
        let host = isProtected ? (protectedHost ?? openHost) : openHost
        guard child.superview !== host else { return }

        host.addSubview(child)
        setNeedsLayout()
    }
}
