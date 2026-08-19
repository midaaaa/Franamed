//
//  YearRangeFilterSection.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 19.08.2026.
//

import SwiftUI

struct YearRangeFilterSection: View {
    private static let wheelHeight: CGFloat = 180

    let earliestYear: Int
    let currentYear: Int

    @Binding var isEnabled: Bool
    @Binding var yearFrom: Int
    @Binding var yearTo: Int

    var body: some View {
        Section {
            Toggle("Ограничить", isOn: $isEnabled)
            if isEnabled {
                HStack {
                    yearPicker("От", selection: $yearFrom) { newValue in
                        if newValue > yearTo { yearTo = newValue }
                    }
                    yearPicker("До", selection: $yearTo) { newValue in
                        if newValue < yearFrom { yearFrom = newValue }
                    }
                }
                .frame(height: Self.wheelHeight)
            }
        } header: {
            Text("Годы выхода")
        } footer: {
            Text("Диапазон года выхода фильма.")
        }
    }

    private func yearPicker(_ title: String, selection: Binding<Int>, onChange: @escaping (Int) -> Void) -> some View {
        Picker(title, selection: selection) {
            ForEach(earliestYear...currentYear, id: \.self) { year in
                Text("\(year)").tag(year)
            }
        }
        .pickerStyle(.wheel)
        .onChange(of: selection.wrappedValue) { _, newValue in
            onChange(newValue)
        }
    }
}

private struct YearRangeFilterSectionPreview: View {
    @State var isEnabled: Bool
    @State var yearFrom = 1990
    @State var yearTo = 2020

    var body: some View {
        Form {
            YearRangeFilterSection(
                earliestYear: 1950,
                currentYear: 2026,
                isEnabled: $isEnabled,
                yearFrom: $yearFrom,
                yearTo: $yearTo
            )
        }
    }
}

#Preview {
    YearRangeFilterSectionPreview(isEnabled: false)
}
