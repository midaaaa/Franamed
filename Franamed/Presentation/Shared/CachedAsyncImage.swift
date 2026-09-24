//
//  CachedAsyncImage.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct CachedAsyncImage: View {
    let url: URL?
    var isProtected: Bool?
    @State private var loaded: (url: URL, image: UIImage)?

    private var displayed: UIImage? {
        guard let url else { return nil }
        return ImageCache.shared.image(for: url) ?? (loaded?.url == url ? loaded?.image : nil)
    }

    var body: some View {
        Group {
            if let isProtected {
                ProtectedImage(image: displayed, isProtected: isProtected)
                    .overlay {
                        if displayed == nil { ProgressView().tint(.white) }
                    }
            } else if let uiImage = displayed {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url, ImageCache.shared.image(for: url) == nil,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let downloadedImage = UIImage(data: data) else { return }

        ImageCache.shared.store(downloadedImage, for: url)
        loaded = (url, downloadedImage)
    }
}

#Preview {
    CachedAsyncImage(url: URL(string: "https://picsum.photos/seed/cached-preview/1280/720"))
}
