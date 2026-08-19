//
//  Language.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 19.08.2026.
//

import Foundation

struct Language: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }
}
