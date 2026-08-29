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
    @Binding var showsMesh: Bool
    @Binding var hapticsEnabled: Bool
    @Binding var tintsPaper: Bool

    var body: some View {
        VStack(spacing: 6) {
            TearFrameRateBadge(probe: probe)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .allowsHitTesting(false)

            HStack(spacing: 6) {
                toggle("меш", isOn: showsMesh) { showsMesh.toggle() }
                toggle("гаптика", isOn: hapticsEnabled) {
                    hapticsEnabled.toggle()
                    Haptics.isEnabled = hapticsEnabled
                }
                toggle("бумага", isOn: tintsPaper) { tintsPaper.toggle() }
            }
        }
        .padding(.top, 8)
    }

    private func toggle(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Color.green : Color.red)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif
