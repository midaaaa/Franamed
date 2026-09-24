//
//  MediaDetails.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import Foundation

struct MediaDetails: Equatable, Sendable {
    var runtimeMinutes: Int?
    var firstYear: Int?
    var lastYear: Int?
    var seasonCount: Int?
    var isInProduction = false
    var isCanceled = false
    var certification: String?
    var authors: [String] = []
}
