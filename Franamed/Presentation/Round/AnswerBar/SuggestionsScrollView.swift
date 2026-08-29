//
//  SuggestionsScrollView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI
import UIKit

struct SuggestionsScrollView: UIViewRepresentable {
    let rows: [SuggestionRow]
    let onSelect: (MediaItem) -> Void
    @Binding var revealedHeight: CGFloat
    @Binding var totalContentHeight: CGFloat
    let availableWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(revealedHeight: $revealedHeight)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = SelfSizingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false

        let hosting = UIHostingController(rootView: SuggestionRowsView(rows: [], onSelect: { _ in }))
        hosting.safeAreaRegions.remove(.keyboard)
        hosting.view.backgroundColor = .clear
        hosting.view.isOpaque = false
        context.coordinator.hostingController = hosting
        scrollView.hostingView = hosting.view
        scrollView.addSubview(hosting.view)
        return scrollView
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        uiView.delegate = nil
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let scrollView = scrollView as? SelfSizingScrollView else { return }
        let coordinator = context.coordinator
        guard let hosting = coordinator.hostingController else { return }

        let slotHeight = suggestionsContentHeight(rows: maxVisibleSuggestions)
        coordinator.slotHeight = slotHeight

        let style: UIUserInterfaceStyle = context.environment.colorScheme == .dark ? .dark : .light
        let rowIDs = rows.map(\.id)
        let rowsChanged = coordinator.lastRowIDs != rowIDs
        guard rowsChanged || coordinator.lastWidth != availableWidth || coordinator.lastStyle != style
        else { return }

        coordinator.lastRowIDs = rowIDs
        coordinator.lastWidth = availableWidth
        coordinator.lastStyle = style

        hosting.overrideUserInterfaceStyle = style
        hosting.rootView = SuggestionRowsView(rows: rows, onSelect: onSelect)

        var measuredHeight = suggestionsContentHeight(rows: rows.count)
        if availableWidth > 0 {
            let fitting = hosting.sizeThatFits(in: CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            if fitting.height > 0 {
                measuredHeight = fitting.height
            }
        }

        scrollView.contentHeight = measuredHeight
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()

        let minHeight = min(measuredHeight, suggestionsContentHeight(rows: minVisibleSuggestions))
        scrollView.contentInset.top = max(0, slotHeight - minHeight)

        guard rowsChanged else {
            DispatchQueue.main.async { totalContentHeight = measuredHeight }
            return
        }

        let targetReveal = min(max(revealedHeight, minHeight), min(measuredHeight, slotHeight))
        coordinator.isProgrammaticScroll = true
        scrollView.contentOffset = CGPoint(x: 0, y: targetReveal - slotHeight)
        coordinator.isProgrammaticScroll = false
        DispatchQueue.main.async {
            withAnimation(.snappy) { revealedHeight = targetReveal }
            totalContentHeight = measuredHeight
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<SuggestionRowsView>?
        let revealedHeightBinding: Binding<CGFloat>
        var slotHeight: CGFloat = 0
        var lastRowIDs: [AnyHashable] = []
        var lastWidth: CGFloat = -1
        var lastStyle: UIUserInterfaceStyle?
        var isProgrammaticScroll = false

        init(revealedHeight: Binding<CGFloat>) {
            self.revealedHeightBinding = revealedHeight
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isProgrammaticScroll else { return }
            let revealed = slotHeight + scrollView.contentOffset.y
            let clamped = min(slotHeight, max(0, revealed))
            revealedHeightBinding.wrappedValue = clamped
        }
    }
}

private struct SuggestionsScrollViewPreviewContainer: View {
    let rows: [SuggestionRow]
    @State private var revealedHeight: CGFloat = suggestionsContentHeight(rows: maxVisibleSuggestions)
    @State private var totalContentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            SuggestionsScrollView(
                rows: rows,
                onSelect: { _ in },
                revealedHeight: $revealedHeight,
                totalContentHeight: $totalContentHeight,
                availableWidth: proxy.size.width
            )
        }
        .frame(height: suggestionsContentHeight(rows: maxVisibleSuggestions))
        .background(.thinMaterial)
        .padding()
    }
}

#Preview("Scroll list") {
    SuggestionsScrollViewPreviewContainer(rows: PreviewSuggestions.mixed.map(SuggestionRow.media))
}

#Preview("Nothing found") {
    SuggestionsScrollViewPreviewContainer(rows: [.empty])
}
