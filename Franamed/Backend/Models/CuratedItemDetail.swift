//
//  CuratedItemDetail.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct CuratedItemDetail: Codable, Sendable {
    let item: CuratedItem
    let images: [CuratedImage]
}
