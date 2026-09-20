//
//  SafariSheet.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 20.09.2026.
//

import SwiftUI
import SafariServices

struct WebSearchLink: Identifiable {
    let url: URL
    var id: URL { url }

    init?(query: String) {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { return nil }
        self.url = url
    }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url, configuration: SFSafariViewController.Configuration())
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
