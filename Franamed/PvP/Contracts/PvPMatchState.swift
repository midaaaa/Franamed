//
//  PvPMatchState.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

// MARK: - State

struct PvPMatchState: Sendable, Equatable {
    var code: String
    var you: String?
    var phase: PvPMatchPhase
    var link: PvPLinkMode
    var settings: PvPSettings?
    var players: [PvPMatchPlayer]
    var film: PvPMatchFilm?
    var preparation: PvPMatchPreparation?
    var reveal: PvPMatchReveal?
    var standings: [PvPStanding]
    var duel: PvPMatchDuel?
    var pause: PvPMatchPause?
    var result: PvPMatchResult?
    var notice: PvPMatchNotice?
    var seq: Int
    var snapshotSeq: Int

    init(code: String) {
        self.code = code
        self.you = nil
        self.phase = .connecting
        self.link = .connecting
        self.settings = nil
        self.players = []
        self.film = nil
        self.preparation = nil
        self.reveal = nil
        self.standings = []
        self.duel = nil
        self.pause = nil
        self.result = nil
        self.notice = nil
        self.seq = -1
        self.snapshotSeq = -1
    }

    var kind: PvPRoomKind? { settings?.kind }

    var me: PvPMatchPlayer? { players.first { $0.isYou } }

    var isHost: Bool { me?.isHost ?? false }

    var opponents: [PvPMatchPlayer] { players.filter { !$0.isYou } }

    func player(_ uid: String) -> PvPMatchPlayer? { players.first { $0.uid == uid } }
}

// MARK: - Phase

enum PvPMatchPhase: Sendable, Equatable {
    case connecting
    case lobby
    case loading
    case ready
    case countdown
    case playing
    case reveal
    case finished
    case closed(PvPMatchClosure)
}

enum PvPMatchClosure: Sendable, Equatable {
    case disconnected
    case left
    case replaced
    case kicked
    case roomClosed
    case removedForFlooding
    case refused(code: String)
    case failed(String)
}

// MARK: - Players

struct PvPMatchPlayer: Sendable, Equatable, Identifiable {
    let uid: String
    var name: String
    var alias: String
    var icon: String
    var color: String
    var isHost: Bool
    var isYou: Bool
    var ready: Bool
    var connection: PvPConnection
    var left: Bool
    var joinedAt: Int64
    var forfeitAt: Date?

    var id: String { uid }
}

// MARK: - Film

struct PvPMatchFilm: Sendable, Equatable {
    let number: Int
    let total: Int
    var timeLimit: TimeInterval
    var startsAt: Date
    var endsAt: Date
    var resumesAt: Date?
    var deadlineCut: Bool
    var participants: [String]
    var progress: [PvPProgress]
    var frames: [PvPFrame]?
    var yourFrame: Int?
    var yourStatus: PvPFilmStatus?
    var lastGuess: PvPMatchGuess?
    var answering: Bool

    var isParticipating: Bool { frames != nil }

    var visibleFrames: ArraySlice<PvPFrame> {
        guard let frames, let yourFrame else { return [] }
        return frames.prefix(max(0, min(yourFrame, frames.count)))
    }

    func progress(of uid: String) -> PvPProgress? { progress.first { $0.uid == uid } }
}

struct PvPMatchGuess: Sendable, Equatable {
    let frame: Int
    let correct: Bool
}

// MARK: - Preparation

enum PvPPreparationStatus: Sendable, Equatable {
    case loading
    case ready
    case broken(index: Int)
}

struct PvPMatchPreparation: Sendable, Equatable {
    let film: Int
    let total: Int
    var frames: [PvPFrame]
    var spares: [PvPFrame]
    var status: PvPPreparationStatus
}

// MARK: - Reveal, duel, pause

struct PvPMatchReveal: Sendable, Equatable {
    let film: Int
    let answer: PvPAnswer
    let results: [PvPFilmResult]
    let standings: [PvPStanding]
    let duel: PvPDuelDamage?
    let nextAt: Date?
}

struct PvPMatchDuel: Sendable, Equatable {
    var hp: [String: Int]
    var maxHP: Int
    var multiplier: Double
}

struct PvPMatchPause: Sendable, Equatable {
    var pausedAt: Date
    var remaining: TimeInterval
    var autoResumeAt: Date
}

struct PvPMatchNotice: Sendable, Equatable {
    let code: String
    let message: String
    let at: Date
}
