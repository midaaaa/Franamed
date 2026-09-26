//
//  TicketDebugOverlay.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

#if DEBUG
struct TicketDebugOverlay: View {
    let probe: TearFrameRateProbe

    var body: some View {
        TearFrameRateBadge(probe: probe)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .allowsHitTesting(false)
            .padding(.top, 8)
    }
}
#endif
