//
//  AnswerInputBar.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct AnswerInputBar: View {
    @Binding var answerText: String
    let searchResults: [MediaItem]
    let hasSearched: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSelectSuggestion: (MediaItem) -> Void
    let onSubmit: () -> Void
    let onAnswerTextChange: () async -> Void
    var onVisibleHeightChange: ((CGFloat) -> Void)? = nil
    var hasOutcome: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var revealedHeight: CGFloat = 0

    @ViewBuilder
    private var barBackground: some View {
        let shape = RoundedRectangle(cornerRadius: suggestionRowHeight / 2, style: .continuous)

        shape.fill(Color.clear)
            .frame(height: suggestionRowHeight + revealedHeight)
            .glassEffect(.regular, in: shape)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            barBackground
                .id(colorScheme)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onVisibleHeightChange?($0) }

            VStack(spacing: 0) {
                AnswerSuggestionsView(
                    items: searchResults,
                    hasSearched: hasSearched,
                    revealedHeight: $revealedHeight,
                    onSelect: onSelectSuggestion
                )
                .id(colorScheme)

                TextField("Your guess", text: $answerText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused(isFocused)
                    .onSubmit(onSubmit)
                    .task(id: answerText) { await onAnswerTextChange() }
                    .padding(.leading, suggestionsLeadingInset)
                    .padding(.trailing, 44)
                    .frame(height: suggestionRowHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: hasOutcome) { _, newValue in
            guard newValue, revealedHeight != 0 else { return }
            withAnimation(.snappy) { revealedHeight = 0 }
        }
    }
}

private struct AnswerInputBarPreviewContainer: View {
    let searchResults: [MediaItem]
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
