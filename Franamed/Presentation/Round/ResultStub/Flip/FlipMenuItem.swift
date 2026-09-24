//
//  FlipMenuItem.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.09.2026.
//

import SwiftUI

struct FlipMenuItem: Identifiable {
    let title: String
    let systemImage: String
    let action: () -> Void

    var id: String { title }
}
