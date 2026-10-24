//
//  VerticalToolbarReader.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.10.2026.
//

import SwiftUI

extension View {
    func readsVerticalToolbar(_ isVertical: Binding<Bool>) -> some View {
        modifier(VerticalToolbarReader(isVertical: isVertical))
    }
}

private struct VerticalToolbarReader: ViewModifier {
    @Binding var isVertical: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(EdgeReader(isVertical: $isVertical))
        } else {
            content
        }
    }
}

@available(iOS 27.1, *)
private struct EdgeReader: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var edge
    @Binding var isVertical: Bool

    func body(content: Content) -> some View {
        content.onChange(of: edge != nil, initial: true) { _, vertical in isVertical = vertical }
    }
}
