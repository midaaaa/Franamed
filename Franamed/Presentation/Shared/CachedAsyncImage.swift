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
    @State private var uiImage: UIImage?

    private var displayed: UIImage? {
        uiImage ?? url.flatMap { ImageCache.shared.image(for: $0) }
    }

    var body: some View {
        Group {
            if let isProtected {
                ProtectedImage(image: displayed, isProtected: isProtected)
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
        guard let url else {
            uiImage = nil
            return
        }

        if let cachedImage = ImageCache.shared.image(for: url) {
            uiImage = cachedImage
            return
        }

        uiImage = nil

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let downloadedImage = UIImage(data: data) else {
            return
        }

        ImageCache.shared.store(downloadedImage, for: url)
        uiImage = downloadedImage
    }
}

#Preview {
    CachedAsyncImage(url: URL(string: "https://picsum.photos/seed/cached-preview/1280/720"))
}
