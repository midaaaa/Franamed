//
//  PlaylistHost.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.10.2026.
//

import SwiftUI
import UIKit

final class PlaylistHost: UIHostingController<AnyView> {
    var playlistID: String?
    var pinnedToolbarItems: [UIBarButtonItem]?
    var clampsScroll = false

    var scrollView: UIScrollView? { view.firstScrollView }

    override var toolbarItems: [UIBarButtonItem]? {
        get { pinnedToolbarItems ?? super.toolbarItems }
        set { super.toolbarItems = newValue }
    }

    override func setToolbarItems(_ toolbarItems: [UIBarButtonItem]?, animated: Bool) {
        super.setToolbarItems(pinnedToolbarItems ?? toolbarItems, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard clampsScroll, let navigation = navigationController as? PlaylistNavigationController,
              !navigation.isTransitioning, navigation.topViewController === self, let scroll = scrollView else { return }
        navigation.settledBottomInset = scroll.adjustedContentInset.bottom
        guard !navigation.isToolbarHidden, !scroll.isTracking, !scroll.isDecelerating,
              scroll.contentOffset.y > scroll.maxOffsetY + 0.5 else { return }
        scroll.contentOffset.y = scroll.maxOffsetY
    }
}

private extension UIView {
    var firstScrollView: UIScrollView? {
        if let scroll = self as? UIScrollView { return scroll }
        for subview in subviews {
            if let scroll = subview.firstScrollView { return scroll }
        }
        return nil
    }
}

private extension UIScrollView {
    var maxOffsetY: CGFloat {
        max(contentSize.height + adjustedContentInset.bottom - bounds.height, -adjustedContentInset.top)
    }
}
