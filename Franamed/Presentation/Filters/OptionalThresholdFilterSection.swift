//
//  OptionalThresholdFilterSection.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 19.08.2026.
//

import SwiftUI

struct OptionalThresholdFilterSection: View {
    let title: String
    let footer: String
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    let formattedValue: (Double) -> String

    @Binding var isEnabled: Bool
    @Binding var value: Double?

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { value ?? defaultValue },
            set: { value = $0 }
        )
    }

    var body: some View {
        Section {
            Toggle("Ограничить", isOn: $isEnabled)
            if isEnabled {
                HStack {
                    Slider(value: sliderBinding, in: range, step: step) {
                        Text(title)
                    }
                    Text(formattedValue(sliderBinding.wrappedValue))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
        .onChange(of: isEnabled) { _, newValue in
            if newValue, value == nil {
                value = defaultValue
            }
        }
    }
}

private struct OptionalThresholdFilterSectionPreview: View {
    @State var isEnabled: Bool
    @State var value: Double?

    var body: some View {
        Form {
            OptionalThresholdFilterSection(
                title: "Рейтинг",
                footer: "Минимальная оценка на TMDB.",
                range: 0...10,
                step: 0.5,
                defaultValue: 6,
                formattedValue: { $0.formatted() },
                isEnabled: $isEnabled,
                value: $value
            )
        }
    }
}

#Preview {
    OptionalThresholdFilterSectionPreview(isEnabled: false, value: nil)
}
