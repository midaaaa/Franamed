//
//  FoldReader.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.10.2026.
//

import SwiftUI

extension View {
    func readsHorizontalFold(_ fold: Binding<ClosedRange<CGFloat>?>) -> some View {
        modifier(FoldReader(fold: fold))
    }
}

private struct FoldReader: ViewModifier {
    @Binding var fold: ClosedRange<CGFloat>?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: ClosedRange<CGFloat>?.self) { proxy in
                proxy.reservedRegions(kind: .division)
                    .first { $0.frame.width > $0.frame.height }
                    .map { $0.frame.minY...$0.frame.maxY }
            } action: { fold = $0 }
        } else {
            content
        }
    }
}
