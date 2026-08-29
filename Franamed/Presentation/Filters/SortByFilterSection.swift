//
//  SortByFilterSection.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct SortByFilterSection: View {
    @Binding var sortBy: SortBy
    let mediaType: MediaType

    var body: some View {
        Section {
            Picker("Сортировка", selection: $sortBy) {
                ForEach(SortBy.allCases, id: \.self) { sortBy in
                    Text(sortBy.displayName).tag(sortBy)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Сортировка")
        } footer: {
            Text("Определяет, из каких \(mediaType.pluralLowercased) собирается раунд: "
                 + "самых популярных, высокооценённых или новых.")
        }
    }
}
