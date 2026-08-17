//
//  CachedAsyncImage.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import SwiftUI

struct CachedAsyncImage: View {
    let url: URL?

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
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
