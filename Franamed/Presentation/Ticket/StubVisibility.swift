//
//  StubVisibility.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct StubVisibility: ViewModifier {
    @Environment(\.ticketStubIsAway) private var isAway
    let isHidden: Bool

    func body(content: Content) -> some View {
        content.opacity(isAway || isHidden ? 0 : 1)
    }
}

extension EnvironmentValues {
    @Entry var ticketStubIsAway = false
}
