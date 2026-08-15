//
//  NewGameButton.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct NewGameButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("New game")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: suggestionRowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(.accentColor).interactive(),
            in: RoundedRectangle(cornerRadius: suggestionRowHeight / 2)
        )
    }
}

#Preview {
    NewGameButton(action: {})
        .padding()
}
