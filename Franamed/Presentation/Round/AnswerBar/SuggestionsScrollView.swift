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

    func makeUIView(context: Context) -> SuggestionsHitTestContainer {
        let container = SuggestionsHitTestContainer()
        let scrollView = SelfSizingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        scrollView.delaysContentTouches = false

        let hosting = UIHostingController(rootView: SuggestionRowsView(rows: [], onSelect: { _ in }))
        hosting.safeAreaRegions.remove(.keyboard)
        hosting.view.backgroundColor = .clear
        hosting.view.isOpaque = false
        context.coordinator.hostingController = hosting
        scrollView.hostingView = hosting.view
        scrollView.addSubview(hosting.view)
        context.coordinator.scrollView = scrollView
        container.addSubview(scrollView)
        return container
    }

    static func dismantleUIView(_ uiView: SuggestionsHitTestContainer, coordinator: Coordinator) {
        coordinator.scrollView?.delegate = nil
    }

    func updateUIView(_ container: SuggestionsHitTestContainer, context: Context) {
        container.visibleHeight = revealedHeight
        let coordinator = context.coordinator
        guard let scrollView = coordinator.scrollView else { return }
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
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()

        let grid = PixelGrid(displayScale: context.environment.displayScale)
        var measuredHeight = suggestionsContentHeight(rows: rows.count)
        var restHeight = min(measuredHeight, suggestionsContentHeight(rows: minVisibleSuggestions))
        if availableWidth > 0 {
            let fitting = hosting.sizeThatFits(in: CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            if fitting.height > 0 {
                measuredHeight = grid.aligned(fitting.height, rule: .up)
                restHeight = coordinator.restHeight(width: availableWidth, style: style,
                                                    grid: grid, total: measuredHeight)
            }
        }

        scrollView.contentHeight = measuredHeight
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()

        let minHeight = restHeight
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
        weak var scrollView: SelfSizingScrollView?
        let revealedHeightBinding: Binding<CGFloat>
        var slotHeight: CGFloat = 0
        var lastRowIDs: [AnyHashable] = []
        var lastWidth: CGFloat = -1
        var lastStyle: UIUserInterfaceStyle?
        var isProgrammaticScroll = false
        private var rowMeasuringController: UIHostingController<SuggestionRowsView>?
        private var cachedRowHeight: CGFloat?
        private var cachedRowWidth: CGFloat = -1
        private var cachedRowStyle: UIUserInterfaceStyle?

        init(revealedHeight: Binding<CGFloat>) {
            self.revealedHeightBinding = revealedHeight
        }

        func restHeight(width: CGFloat, style: UIUserInterfaceStyle,
                        grid: PixelGrid, total: CGFloat) -> CGFloat {
            let rowHeight = oneLineRowHeight(width: width, style: style) ?? suggestionRowHeight
            let rows = CGFloat(minVisibleSuggestions)
            let cap = grid.aligned(rowHeight * rows + suggestionDividerHeight * (rows - 1), rule: .up)
            return min(total, cap)
        }

        private func oneLineRowHeight(width: CGFloat, style: UIUserInterfaceStyle) -> CGFloat? {
            if let cached = cachedRowHeight, cachedRowWidth == width, cachedRowStyle == style {
                return cached
            }

            let controller = rowMeasuringController ?? {
                let created = UIHostingController(rootView: SuggestionRowsView(rows: [], onSelect: { _ in }))
                created.safeAreaRegions.remove(.keyboard)
                rowMeasuringController = created
                return created
            }()

            controller.overrideUserInterfaceStyle = style
            controller.rootView = SuggestionRowsView(rows: [.empty], onSelect: { _ in })
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            let fitting = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            guard fitting.height > 0 else { return nil }

            cachedRowHeight = fitting.height
            cachedRowWidth = width
            cachedRowStyle = style
            return fitting.height
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
