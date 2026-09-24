//
//  RoundBackdrop.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 24.09.2026.
//

enum RoundBackdrop: String {
    case beam, hall

    var next: RoundBackdrop { self == .beam ? .hall : .beam }
}
