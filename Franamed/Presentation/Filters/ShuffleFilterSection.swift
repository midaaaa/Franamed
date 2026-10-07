//
//  ShuffleFilterSection.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 07.10.2026.
//

import SwiftUI

struct ShuffleFilterSection: View {
    @Binding var shuffle: ShuffleMode

    private var isSmart: Binding<Bool> {
        Binding(
            get: { shuffle == .smart },
            set: { shuffle = $0 ? .smart : .random }
        )
    }

    var body: some View {
        Section {
            Toggle(isOn: isSmart.animation(.snappy)) {
                Label {
                    Text("Умное перемешивание")
                } icon: {
                    ShuffleIcon(mode: shuffle)
                        .symbolEffect(.bounce, value: shuffle)
                }
            }
        } footer: {
            Text(shuffle.summary)
        }
    }
}

#Preview {
    @Previewable @State var shuffle = ShuffleMode.smart
    Form {
        ShuffleFilterSection(shuffle: $shuffle)
    }
}
