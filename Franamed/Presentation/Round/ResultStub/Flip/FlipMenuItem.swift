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
    var doneTitle: String?
    var isDone = false
    let action: () -> Void

    var id: String { title }
    var shownTitle: String { isDone ? doneTitle ?? title : title }
    var shownImage: String { isDone ? "checkmark" : systemImage }
}
