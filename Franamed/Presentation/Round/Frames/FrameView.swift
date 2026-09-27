//
//  FrameView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct FrameView: View {
    let image: UIImage?
    var isWaitingForFrame: Bool = false
    var isProtected: Bool = false
    var hidesSpinnerFromCapture: Bool = false
    let onTapPrevious: () -> Void
    let onTapNext: () -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if let image {
                    ProtectedImage(image: image, isProtected: isProtected)
                } else if isWaitingForFrame {
                    WaitingSpinner(hidesFromCapture: hidesSpinnerFromCapture)
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
        image: UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        },
        onTapPrevious: {},
        onTapNext: {}
    )
}

#Preview("Frame — black, no wait") {
    FrameView(image: nil, onTapPrevious: {}, onTapNext: {})
}

#Preview("Frame — waiting (spinner)") {
    FrameView(image: nil, isWaitingForFrame: true, onTapPrevious: {}, onTapNext: {})
}
