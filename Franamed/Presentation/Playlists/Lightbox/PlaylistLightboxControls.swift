//
//  PlaylistLightboxControls.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import SwiftUI

struct PlaylistLightboxControls: ToolbarContent {
    let actions: [FlipMenuItem]
    let areActionsEnabled: Bool
    let onClose: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close, action: onClose)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            ForEach(actions) { action in
                Button(action.title, systemImage: action.systemImage, action: action.action)
                    .disabled(!areActionsEnabled)
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
    }
}
