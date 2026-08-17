//
//  FrameView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct FrameView: View {
    let imageURL: URL?
    var isWaitingForFrame: Bool = false
    let onTapPrevious: () -> Void
    let onTapNext: () -> Void

    var body: some View {
        Color.black
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if let imageURL {
                    CachedAsyncImage(url: imageURL)
                } else if isWaitingForFrame {
                    ProgressView().tint(.white)
                }
            }
            .overlay {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onTapPrevious() }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onTapNext() }
                }
            }
    }
}

#Preview("Frame") {
    FrameView(
        imageURL: URL(string: "https://picsum.photos/seed/backdrop1/1280/720"),
        onTapPrevious: {},
        onTapNext: {}
    )
}

#Preview("Frame — black, no wait") {
    FrameView(imageURL: nil, onTapPrevious: {}, onTapNext: {})
}

#Preview("Frame — waiting (spinner)") {
    FrameView(imageURL: nil, isWaitingForFrame: true, onTapPrevious: {}, onTapNext: {})
}
