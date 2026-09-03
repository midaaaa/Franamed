//
//  CurationReportEntry.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct CurationReportEntry: Codable, Sendable, Identifiable {
    let imageId: Int
    let mediaKey: String
    let title: String
    let filePath: String
    let reason: ReportReason
    let weight: Double
    let imageStatus: ImageStatus
    let totalReportWeight: Double
    let createdAt: Double

    var id: String { "\(imageId)-\(createdAt)" }
}
