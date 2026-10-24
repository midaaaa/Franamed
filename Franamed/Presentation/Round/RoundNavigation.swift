//
//  RoundNavigation.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.10.2026.
//

import SwiftUI
import UIKit

struct RoundNavigation<Content: View>: UIViewControllerRepresentable {
    @ViewBuilder var content: Content

    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: RoundHost(rootView: hosted(context)))
    }

    func updateUIViewController(_ navigation: UINavigationController, context: Context) {
        (navigation.viewControllers.first as? RoundHost)?.rootView = hosted(context)
    }

    private func hosted(_ context: Context) -> AnyView {
        AnyView(content
            .providesWindowGeometry()
            .environment(\.resultStubWidth, context.environment.resultStubWidth))
    }
}

private final class RoundHost: UIHostingController<AnyView> {
    override init(rootView: AnyView) {
        super.init(rootView: rootView)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let barTop = isBarCollapsed ? (view.window?.safeAreaInsets.top ?? 0) - systemTop : 0
        if additionalSafeAreaInsets.top != barTop { additionalSafeAreaInsets.top = barTop }
    }

    private var systemTop: CGFloat { view.safeAreaInsets.top - additionalSafeAreaInsets.top }

    private var isBarCollapsed: Bool {
        guard let bar = navigationController?.navigationBar, !bar.isHidden else { return false }
        return bar.frame.height == 0
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              !frame.isEmpty, let screen = note.object as? UIScreen else { return }
        let isUndocked = frame.width < screen.bounds.width - 1
        safeAreaRegions = isUndocked ? .container : .all
    }
}
