//
//  ProfileSnapshot.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

struct ProfileSnapshot: Codable, Sendable {
    let user: BackendUser
    let budget: AttemptBudget
}
