//
//  Backdrop.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

struct Backdrop: Codable, Identifiable {
    var id: String { filePath }
    let filePath: String
}
