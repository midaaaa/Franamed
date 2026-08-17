//
//  ResultBanner.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct ResultBanner: View {
    let outcome: RoundOutcome
    let movieTitle: String

    var body: some View {
        VStack(spacing: 8) {
            Label(
                outcome == .correct ? "Correct" : "Incorrect",
                systemImage: outcome == .correct ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(outcome == .correct ? .green : .red)

            Text(movieTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(.horizontal)
    }
}

#Preview("Result banner") {
    VStack(spacing: 24) {
        ResultBanner(outcome: .correct, movieTitle: "Everything Everywhere All at Once")
        ResultBanner(outcome: .incorrect, movieTitle: "Up")
    }
}
