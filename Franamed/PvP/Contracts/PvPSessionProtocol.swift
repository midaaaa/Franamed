//
//  PvPSessionProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

protocol PvPSessionProtocol: Sendable {
    func states() -> AsyncStream<PvPMatchState>

    func connect() async
    func disconnect() async

    func ready() async
    func unready() async
    func guess(tmdbId: Int?, mediaType: MediaType, text: String) async
    func skip() async
    func frameBroken(index: Int) async
    func setAway(_ away: Bool) async
    func leave() async

    func changeSettings(films: Int?, frames: Int?, timeLimitSec: Int?) async
    func start() async
    func pause() async
    func resume() async
    func kick(uid: String) async
    func hideName(uid: String) async
    func newMatch() async
}

extension PvPSessionProtocol {
    func guess(tmdbId: Int, mediaType: MediaType) async {
        await guess(tmdbId: tmdbId, mediaType: mediaType, text: "")
    }
}
