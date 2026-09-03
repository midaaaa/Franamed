//
//  ConsumeAttemptResult.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct ConsumeAttemptResult: Codable, Sendable {
    let allowed: Bool
    let budget: AttemptBudget
}
