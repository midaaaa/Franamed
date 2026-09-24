//
//  StubMenuItem.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.09.2026.
//

import SwiftUI

struct StubMenuItem: Identifiable {
    let title: String
    let systemImage: String
    let action: () -> Void

    var id: String { title }
}
