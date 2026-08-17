//
//  Array+Safe.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
