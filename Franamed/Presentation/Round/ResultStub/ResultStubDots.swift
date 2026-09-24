//
//  ResultStubDots.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

import SwiftUI

struct ResultStubDots: View {
    let used: Int
    let total: Int
    let isCorrect: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(color(at: index))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func color(at index: Int) -> Color {
        guard index < used else { return .black.opacity(0.18) }
        if index == used - 1 { return isCorrect ? .green : .red }
        return .black.opacity(0.45)
    }
}
