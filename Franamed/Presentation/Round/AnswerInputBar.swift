//
//  AnswerInputBar.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct AnswerInputBar: View {
    @Binding var answerText: String
    let searchResults: [Movie]
    let hasSearched: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSelectSuggestion: (Movie) -> Void
    let onSubmit: () -> Void
    let onAnswerTextChange: () async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var revealedHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: suggestionRowHeight / 2)
                .fill(Color.clear)
                .frame(height: suggestionRowHeight + revealedHeight)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: suggestionRowHeight / 2))
                .compositingGroup()
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .id(colorScheme)  // forces full theme switch redraw

            VStack(spacing: 0) {
                AnswerSuggestionsView(
                    movies: searchResults,
                    hasSearched: hasSearched,
                    revealedHeight: $revealedHeight,
                    onSelect: onSelectSuggestion
                )
                .id(colorScheme)

                ZStack(alignment: .trailing) {
                    TextField("Your guess", text: $answerText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .focused(isFocused)
                        .onSubmit(onSubmit)
                        .task(id: answerText) { await onAnswerTextChange() }
                        .padding(.leading, suggestionsLeadingInset)
                        .padding(.trailing, 44)
                        .frame(height: suggestionRowHeight)

                    Button(action: onSubmit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .glassEffect(.regular.tint(.accentColor), in: Circle())
                    .padding(.trailing, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AnswerInputBarPreviewContainer: View {
    let searchResults: [Movie]
    let hasSearched: Bool
    @State private var answerText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        AnswerInputBar(
            answerText: $answerText,
            searchResults: searchResults,
            hasSearched: hasSearched,
            isFocused: $isFocused,
            onSelectSuggestion: { answerText = $0.title },
            onSubmit: {},
            onAnswerTextChange: {}
        )
        .padding()
    }
}

#Preview("Idle") {
    AnswerInputBarPreviewContainer(searchResults: [], hasSearched: false)
}

#Preview("With suggestions") {
    AnswerInputBarPreviewContainer(searchResults: PreviewSuggestions.mixed, hasSearched: true)
}

#Preview("Nothing found") {
    AnswerInputBarPreviewContainer(searchResults: [], hasSearched: true)
}
