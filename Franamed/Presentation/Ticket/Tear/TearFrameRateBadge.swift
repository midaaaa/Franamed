//
//  TearFrameRateBadge.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import SwiftUI

struct TearFrameRateBadge: View {
    let probe: TearFrameRateProbe

    private let budget: Double = 1000.0 / 60.0

    var body: some View {
        VStack(spacing: 5) {
            pill(frameLabel, tint: frameTint)
            HStack(spacing: 6) {
                pill(msLabel("cpu", cpu), tint: msTint(cpu))
                pill(msLabel("wait", wait), tint: wait >= budget / 2 ? .secondary : .green)
                pill(msLabel("gpu", gpu), tint: msTint(gpu))
            }
        }
    }

    private var cpu: Double { probe.isIdle ? probe.sessionWorstCPU : probe.worstCPU }
    private var wait: Double { probe.isIdle ? probe.sessionWorstWait : probe.worstWait }
    private var gpu: Double { probe.isIdle ? probe.sessionWorstGPU : probe.worstGPU }

    private func pill(_ text: String, tint: Color) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }

    private var frameLabel: String {
        if probe.isIdle {
            let worst = probe.sessionWorstFPS
            guard worst > 0 else { return "idle" }
            return "min \(Int(worst)) · avg \(Int(probe.sessionAverageFPS))"
        }
        return "min \(Int(probe.worstFPS)) · avg \(Int(probe.averageFPS))"
    }

    private func msLabel(_ name: String, _ value: Double) -> String {
        value > 0 ? "\(name) \(String(format: "%.1f", value))" : "\(name) —"
    }

    private var frameTint: Color {
        let worst = probe.isIdle ? probe.sessionWorstFPS : probe.worstFPS
        guard worst > 0 else { return .secondary }
        if worst >= 55 { return .green }
        return worst >= 45 ? .orange : .red
    }

    private func msTint(_ value: Double) -> Color {
        guard value > 0 else { return .secondary }
        if value >= budget { return .red }
        return value >= budget / 2 ? .orange : .green
    }
}
