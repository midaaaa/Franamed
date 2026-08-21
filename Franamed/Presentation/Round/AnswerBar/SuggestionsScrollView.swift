//
//  SuggestionsScrollView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI
import UIKit

final class SelfSizingScrollView: UIScrollView {
    var hostingView: UIView?
    var contentHeight: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(bounds.width, 1)
        contentSize = CGSize(width: width, height: contentHeight)
        hostingView?.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
    }
}

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

        let hosting = UIHostingController(rootView: AnyView(EmptyView()))
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

        coordinator.hostingController?.overrideUserInterfaceStyle =
            context.environment.colorScheme == .dark ? .dark : .light

        let frameHeight = suggestionsContentHeight(rows: maxVisibleSuggestions)
        let minBudget = suggestionsContentHeight(rows: minVisibleSuggestions)
        coordinator.frameHeight = frameHeight

        coordinator.hostingController?.rootView = AnyView(rowsContent)

        let estimatedHeight = suggestionsContentHeight(rows: rows.count)
        var measuredHeight = estimatedHeight
        if availableWidth > 0, let hosting = coordinator.hostingController {
            let fitting = hosting.sizeThatFits(in: CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            if fitting.height > 0 {
                measuredHeight = fitting.height
            }
        }

        let revealCap = min(measuredHeight, frameHeight)
        let minHeight = min(measuredHeight, minBudget)

        scrollView.contentHeight = measuredHeight
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()

        let inset = max(0, frameHeight - minHeight)
        let rowIDs = rows.map(\.id)
        if coordinator.lastRowIDs != rowIDs {
            coordinator.lastRowIDs = rowIDs
            let targetReveal = min(max(revealedHeight, minHeight), revealCap)
            scrollView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: 0, right: 0)
            coordinator.isProgrammaticScroll = true
            scrollView.contentOffset = CGPoint(x: 0, y: targetReveal - frameHeight)
            coordinator.isProgrammaticScroll = false
            DispatchQueue.main.async {
                withAnimation(.snappy) { revealedHeight = targetReveal }
                totalContentHeight = measuredHeight
            }
        } else {
            scrollView.contentInset.top = inset
            DispatchQueue.main.async {
                totalContentHeight = measuredHeight
            }
        }
    }

    private var rowsContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(for: row)
                    .padding(.vertical, 12)
                    .padding(.leading, suggestionsLeadingInset)
                    .padding(.trailing, 12)

                if index != rows.count - 1 {
                    Divider()
                        .frame(height: suggestionDividerHeight)
                        .padding(.leading, suggestionsLeadingInset)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(for row: SuggestionRow) -> some View {
        switch row {
        case .media(let item):
            Button {
                onSelect(item)
            } label: {
                Text(item.title)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .empty:
            Text("Nothing found")
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<AnyView>?
        let revealedHeightBinding: Binding<CGFloat>
        var frameHeight: CGFloat = 0
        var lastRowIDs: [AnyHashable] = []
        var isProgrammaticScroll = false

        init(revealedHeight: Binding<CGFloat>) {
            self.revealedHeightBinding = revealedHeight
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isProgrammaticScroll else { return }
            let revealed = frameHeight + scrollView.contentOffset.y
            let clamped = min(frameHeight, max(0, revealed))
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
