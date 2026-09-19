//
//  AnswerSuggestionsView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

private let suggestionFadeHeight: CGFloat = 16
private let suggestionsGlassEdge: CGFloat = 1

private struct SuggestionsClipShape: Shape {
    let cornerRadius: CGFloat
    let edgeInset: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = max(0, min(edgeInset, rect.width / 2, rect.height))
        let box = CGRect(x: rect.minX + inset, y: rect.minY + inset,
                         width: max(rect.width - inset * 2, 0),
                         height: max(rect.height - inset, 0))
        let radius = max(0, min(cornerRadius - inset, box.width / 2, box.height))
        return UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(topLeading: radius, bottomLeading: 0,
                                              bottomTrailing: 0, topTrailing: radius),
            style: .continuous
        ).path(in: box)
    }
}

private struct SuggestionsRevealMask: View {
    let revealedHeight: CGFloat
    let showsFade: Bool

    private var shape: SuggestionsClipShape {
        SuggestionsClipShape(cornerRadius: min(suggestionRowHeight / 2, revealedHeight),
                             edgeInset: suggestionsGlassEdge)
    }

    var body: some View {
        Group {
            if showsFade {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: min(suggestionFadeHeight, revealedHeight))
                }
            } else {
                Rectangle()
            }
        }
        .frame(height: revealedHeight)
        .clipShape(shape)
    }
}

private struct SuggestionsSlot<Content: View>: View {
    let visibleHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: max(0, visibleHeight))
            .overlay(alignment: .bottom) {
                content.frame(height: suggestionsContentHeight(rows: maxVisibleSuggestions))
            }
    }
}

struct AnswerSuggestionsView: View {
    let items: [MediaItem]
    let hasSearched: Bool
    @Binding var revealedHeight: CGFloat
    let onSelect: (MediaItem) -> Void

    @State private var totalContentHeight: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    private var hasMoreBelow: Bool {
        revealedHeight < totalContentHeight
    }

    private var rows: [SuggestionRow] {
        if items.isEmpty {
            return hasSearched ? [.empty] : []
        }
        return items.map(SuggestionRow.media)
    }

    @ViewBuilder
    private var scrollView: some View {
        let scroll = SuggestionsScrollView(
            rows: rows,
            onSelect: onSelect,
            revealedHeight: $revealedHeight,
            totalContentHeight: $totalContentHeight,
            availableWidth: availableWidth
        )

        scroll.mask(alignment: .bottom) {
            SuggestionsRevealMask(revealedHeight: revealedHeight, showsFade: hasMoreBelow)
        }
    }

    var body: some View {
        SuggestionsSlot(visibleHeight: rows.isEmpty ? 0 : revealedHeight) {
            if rows.isEmpty {
                Color.clear
                    .onAppear {
                        guard revealedHeight != 0 else { return }
                        withAnimation(.snappy) { revealedHeight = 0 }
                    }
            } else {
                scrollView
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 0))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .allowsHitTesting(!rows.isEmpty)
    }
}

private struct AnswerSuggestionsPreviewContainer: View {
    let items: [MediaItem]
    let hasSearched: Bool
    @State private var revealedHeight: CGFloat = 0

    var body: some View {
        AnswerSuggestionsView(items: items, hasSearched: hasSearched, revealedHeight: $revealedHeight, onSelect: { _ in })
            .padding()
            .background(.thinMaterial)
    }
}

#Preview("One-line titles") {
    AnswerSuggestionsPreviewContainer(items: PreviewSuggestions.oneLine, hasSearched: true)
}

#Preview("Two-line titles") {
    AnswerSuggestionsPreviewContainer(items: PreviewSuggestions.twoLine, hasSearched: true)
}

#Preview("Three-line titles") {
    AnswerSuggestionsPreviewContainer(items: PreviewSuggestions.threeLine, hasSearched: true)
}

#Preview("Mixed lengths") {
    AnswerSuggestionsPreviewContainer(items: PreviewSuggestions.mixed, hasSearched: true)
}

#Preview("Few results") {
    AnswerSuggestionsPreviewContainer(items: PreviewSuggestions.few, hasSearched: true)
}

#Preview("Nothing found") {
    AnswerSuggestionsPreviewContainer(items: [], hasSearched: true)
}

#Preview("Idle") {
    AnswerSuggestionsPreviewContainer(items: [], hasSearched: false)
}
