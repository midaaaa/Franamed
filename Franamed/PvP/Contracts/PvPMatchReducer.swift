//
//  PvPMatchReducer.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

enum PvPMatchEvent: Sendable {
    case transport(PvPTransportEvent)
    case tick
    case preparation(film: Int, PvPPreparationStatus)
    case answerSent(film: Int, frame: Int)
}

protocol PvPMatchReducer: Sendable {
    func reduce(_ state: PvPMatchState, _ event: PvPMatchEvent, now: Date) -> PvPMatchState
    func nextChange(of state: PvPMatchState, now: Date) -> Date?
}
