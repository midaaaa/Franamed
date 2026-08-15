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
    let movies: [Movie]
    let onSelect: (Movie) -> Void
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

        coordinator.hostingController?.rootView = AnyView(rows)

        let estimatedHeight = suggestionsContentHeight(rows: movies.count)
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
        let movieIDs = movies.map(\.id)
        if coordinator.lastMovieIDs != movieIDs {
            coordinator.lastMovieIDs = movieIDs
            let targetReveal = min(max(revealedHeight, minHeight), revealCap)
            scrollView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: 0, right: 0)
            scrollView.contentOffset = CGPoint(x: 0, y: targetReveal - frameHeight)
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

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                Button {
                    onSelect(movie)
                } label: {
                    Text(movie.title)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 12)
                .padding(.leading, suggestionsLeadingInset)
                .padding(.trailing, 12)

                if index != movies.count - 1 {
                    Divider()
                        .frame(height: suggestionDividerHeight)
                        .padding(.leading, suggestionsLeadingInset)
                }
            }
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<AnyView>?
        let revealedHeightBinding: Binding<CGFloat>
        var frameHeight: CGFloat = 0
        var lastMovieIDs: [Int] = []

        init(revealedHeight: Binding<CGFloat>) {
            self.revealedHeightBinding = revealedHeight
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let revealed = frameHeight + scrollView.contentOffset.y
            revealedHeightBinding.wrappedValue = min(frameHeight, max(0, revealed))
        }
    }
}
