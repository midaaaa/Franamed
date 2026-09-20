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
    var releaseYear: String?

    @State private var webSearch: WebSearchLink?

    private var searchQuery: String {
        [movieTitle, releaseYear].compactMap { $0 }.joined(separator: " ")
    }

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
                .contextMenu {
                    Button("Copy title", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = movieTitle
                    }
                    Button("Search the web", systemImage: "magnifyingglass") {
                        webSearch = WebSearchLink(query: searchQuery)
                    }
                }
        }
        .padding(.horizontal)
        .sheet(item: $webSearch) { link in
            SafariSheet(url: link.url).ignoresSafeArea()
        }
    }
}

#Preview("Result banner") {
    VStack(spacing: 24) {
        ResultBanner(outcome: .correct, movieTitle: "Everything Everywhere All at Once", releaseYear: "2022")
        ResultBanner(outcome: .incorrect, movieTitle: "Up", releaseYear: "2009")
    }
}
