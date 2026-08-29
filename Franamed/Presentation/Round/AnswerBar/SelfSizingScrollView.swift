//
//  SelfSizingScrollView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import UIKit

final class SelfSizingScrollView: UIScrollView {
    var hostingView: UIView?
    var contentHeight: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(bounds.width, 1)
        contentSize = CGSize(width: width, height: contentHeight)
        hostingView?.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
    }
}
