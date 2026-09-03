//
//  ScheduledDaily.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct ScheduledDaily: Codable, Sendable, Identifiable {
    let date: String
    let mediaKey: String
    let title: String?
    let scheduledBy: String?

    var id: String { date }
}
