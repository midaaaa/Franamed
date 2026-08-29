//
//  AdultFilterSection.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import SwiftUI

struct AdultFilterSection: View {
    @Binding var includeAdult: Bool
    let mediaType: MediaType

    var body: some View {
        Section {
            Toggle("18+", isOn: $includeAdult)
        } footer: {
            Text("Показывать \(mediaType.pluralLowercased) с рейтингом 18+.")
        }
    }
}
