//
//  PvPResultStore.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

protocol PvPResultStore: Sendable {
    func save(_ result: PvPMatchResult) async
    func results() async -> [PvPMatchResult]
    func remove(id: String) async
}
