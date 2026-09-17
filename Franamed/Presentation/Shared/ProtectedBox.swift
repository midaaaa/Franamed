//
//  ProtectedBox.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.09.2026.
//

import UIKit

final class ProtectedBox: UIView {

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

        protectedHost = Self.makeProtectedHost()
        if let protectedHost {
            protectedHost.clipsToBounds = false
            protectedHost.isUserInteractionEnabled = false
            addSubview(protectedHost)
        } else {
            NSLog("[Shield] не нашёл защищённый слой, содержимое осталось незащищённым")
        }

        openHost.isUserInteractionEnabled = false
        addSubview(openHost)

        child.autoresizingMask = []
        openHost.addSubview(child)
        attachChild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не поддерживается") }

    private static func makeProtectedHost() -> UIView? {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.textContentType = .oneTimeCode
        field.isUserInteractionEnabled = false
        field.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        field.layoutIfNeeded()

        let host = field.subviews.first {
            String(describing: type(of: $0)).contains("CanvasView")
        }
        host?.removeFromSuperview()
        return host
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        protectedHost?.frame = bounds
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
