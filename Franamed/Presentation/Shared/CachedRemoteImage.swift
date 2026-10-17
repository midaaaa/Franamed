//
//  CachedRemoteImage.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

struct CachedRemoteImage: View {
    let url: URL?

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let cached = ImageCache.shared.image(for: url) {
            image = cached
            return
        }
        image = nil
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let loaded = UIImage(data: data) else { return }
        ImageCache.shared.store(loaded, for: url)
        withAnimation(.easeOut(duration: 0.2)) { image = loaded }
    }
}
