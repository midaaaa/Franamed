//
//  DifficultyFilterSection.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct DifficultyFilterSection: View {
    @Binding var frameCount: Int

    private var sliderValue: Binding<Double> {
        Binding(get: { Double(frameCount) }, set: { frameCount = Int($0) })
    }

    var body: some View {
        Section {
            HStack {
                Slider(value: sliderValue, in: 1...6, step: 1) {
                    Text("Сложность")
                }
                Text(frameCount, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 16, alignment: .trailing)
            }
        } header: {
            Text("Сложность")
        } footer: {
            Text("Меньше кадров — сложнее, больше — легче.")
        }
    }
}
