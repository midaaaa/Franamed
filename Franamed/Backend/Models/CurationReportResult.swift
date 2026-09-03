//
//  CurationReportResult.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct CurationReportResult: Codable, Sendable {
    let image: CuratedImage
    let replacement: CuratedImage?
}
