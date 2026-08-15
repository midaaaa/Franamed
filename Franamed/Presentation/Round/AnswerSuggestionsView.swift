//
//  AnswerSuggestionsView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

private struct NothingFoundRow: View {
    var body: some View {
        Text("Nothing found")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: suggestionRowHeight)
            .padding(.leading, suggestionsLeadingInset)
            .padding(.trailing, 12)
    }
}

private let suggestionFadeHeight: CGFloat = 16

private struct SuggestionsRevealMask: View {
    let revealedHeight: CGFloat
    let showsFade: Bool

    var body: some View {
        if showsFade {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(suggestionFadeHeight, revealedHeight))
            }
            .frame(height: revealedHeight)
        } else {
            Rectangle().frame(height: revealedHeight)
        }
    }
}

private struct FixedHeightSlot<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: suggestionsContentHeight(rows: maxVisibleSuggestions))
    }
}

struct AnswerSuggestionsView: View {
    let movies: [Movie]
    let hasSearched: Bool
    @Binding var revealedHeight: CGFloat
    let onSelect: (Movie) -> Void

    @State private var totalContentHeight: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    private var hasMoreBelow: Bool {
        revealedHeight < totalContentHeight
    }

    var body: some View {
        FixedHeightSlot {
            if movies.isEmpty {
                if hasSearched {
                    NothingFoundRow()
                        .onAppear { withAnimation(.snappy) { revealedHeight = suggestionRowHeight } }
                } else {
                    Color.clear
                        .onAppear { withAnimation(.snappy) { revealedHeight = 0 } }
                }
            } else {
                ZStack(alignment: .top) {
                    SuggestionsScrollView(
                        movies: movies,
                        onSelect: onSelect,
                        revealedHeight: $revealedHeight,
                        totalContentHeight: $totalContentHeight,
                        availableWidth: availableWidth
                    )
                    .mask(alignment: .bottom) {
                        SuggestionsRevealMask(revealedHeight: revealedHeight, showsFade: hasMoreBelow)
                    }

                    Color.clear
                        .frame(height: max(0, suggestionsContentHeight(rows: maxVisibleSuggestions) - revealedHeight))
                        .contentShape(Rectangle())
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .allowsHitTesting(!movies.isEmpty)
    }
}

private struct AnswerSuggestionsPreviewContainer: View {
    let movies: [Movie]
    let hasSearched: Bool
    @State private var revealedHeight: CGFloat = 0

    var body: some View {
        AnswerSuggestionsView(movies: movies, hasSearched: hasSearched, revealedHeight: $revealedHeight, onSelect: { _ in })
            .padding()
            .background(.thinMaterial)
    }
}

#Preview("One-line titles") {
    AnswerSuggestionsPreviewContainer(movies: PreviewSuggestions.oneLine, hasSearched: true)
}

#Preview("Two-line titles") {
    AnswerSuggestionsPreviewContainer(movies: PreviewSuggestions.twoLine, hasSearched: true)
}

#Preview("Three-line titles") {
    AnswerSuggestionsPreviewContainer(movies: PreviewSuggestions.threeLine, hasSearched: true)
}

#Preview("Mixed lengths") {
    AnswerSuggestionsPreviewContainer(movies: PreviewSuggestions.mixed, hasSearched: true)
}

#Preview("Few results") {
    AnswerSuggestionsPreviewContainer(movies: PreviewSuggestions.few, hasSearched: true)
}

#Preview("Nothing found") {
    AnswerSuggestionsPreviewContainer(movies: [], hasSearched: true)
}

#Preview("Idle") {
    AnswerSuggestionsPreviewContainer(movies: [], hasSearched: false)
}
