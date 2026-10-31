//
//  PvPMessages.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

// MARK: - Profile and rooms

struct PvPProfile: Codable, Sendable, Equatable {
    let uid: String
    let name: String
    let customName: Bool
    let alias: String
    let icon: String
    let color: String
}

struct PvPProfileUpdate: Encodable, Sendable {
    var name: String?
    var icon: String?
    var color: String?
    var reroll: Bool?
    var generatedName = false

    private enum CodingKeys: String, CodingKey {
        case name, icon, color, reroll
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if generatedName {
            try container.encodeNil(forKey: .name)
        } else {
            try container.encodeIfPresent(name, forKey: .name)
        }
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(reroll, forKey: .reroll)
    }
}

enum PvPRoomKind: String, Codable, Sendable {
    case room
    case duel
}

struct PvPCreateRoom: Encodable, Sendable {
    let kind: PvPRoomKind
    let mediaType: MediaType
    var films: Int?
    var frames: Int?
    var timeLimitSec: Int?
}

struct PvPRoomTicket: Decodable, Sendable, Equatable {
    let code: String?
    let ticket: String
    let socketURL: URL
}

// MARK: - Socket close codes

enum PvPCloseCode: Int, Sendable {
    case left = 4000
    case replaced = 4001
    case kicked = 4003
    case roomClosed = 4004
    case stale = 4008
    case tooManyMessages = 4029
    case removedForFlooding = 4030

    var allowsReconnect: Bool {
        switch self {
        case .stale, .tooManyMessages: true
        case .left, .replaced, .kicked, .roomClosed, .removedForFlooding: false
        }
    }
}

// MARK: - Shared types

enum PvPPhase: String, Codable, Sendable {
    case lobby
    case loading
    case ready
    case reveal
    case countdown
    case playing
    case finished
    case closed
}

enum PvPConnection: String, Codable, Sendable {
    case online
    case away
    case offline
}

enum PvPFilmStatus: String, Codable, Sendable {
    case thinking
    case solved
    case failed
    case out
}

enum PvPFinishReason: String, Codable, Sendable {
    case filmsDone = "films_done"
    case knockout
    case forfeit
    case abandoned
    case draw
}

struct PvPSettings: Codable, Sendable, Equatable {
    let kind: PvPRoomKind
    let mediaType: MediaType
    let films: Int
    let frames: Int
    let timeLimitSec: Int
    let hp: Int?
    let maxFilms: Int?
    var maxPlayers: Int? = nil
}

struct PvPPlayer: Codable, Sendable, Identifiable, Equatable {
    let uid: String
    let name: String
    let alias: String
    let icon: String
    let color: String
    let isHost: Bool
    let ready: Bool
    let connection: PvPConnection
    let left: Bool
    let joinedAt: Int64
    let forfeitInMs: Int?

    var id: String { uid }
}

struct PvPFrame: Codable, Sendable, Equatable {
    let path: String
    let width: Int?
    let height: Int?
}

struct PvPAnswer: Codable, Sendable, Equatable {
    let mediaKey: String
    let tmdbId: Int
    let mediaType: MediaType
    let title: String
    let originalTitle: String
    let year: Int?
    let posterPath: String?
}

struct PvPFilmResult: Codable, Sendable, Equatable {
    let uid: String
    let solvedAtFrame: Int?
    let ms: Int?
    let points: Int
}

struct PvPStanding: Codable, Sendable, Equatable {
    let uid: String
    let place: Int
    let total: Int?
    let hp: Int?
}

struct PvPProgress: Codable, Sendable, Equatable {
    let uid: String
    let frame: Int
    let status: PvPFilmStatus
}

struct PvPDuelDamage: Codable, Sendable, Equatable {
    let multiplier: Double
    let damage: [String: Int]
    let hp: [String: Int]
}

struct PvPDuelState: Codable, Sendable, Equatable {
    let hp: [String: Int]
    let multiplier: Double
}

struct PvPReveal: Codable, Sendable, Equatable {
    let film: Int
    let answer: PvPAnswer
    let results: [PvPFilmResult]
    let standings: [PvPStanding]
    let duel: PvPDuelDamage?
    let nextInMs: Int
}

struct PvPFinishedFilm: Codable, Sendable, Equatable {
    let film: Int
    let answer: PvPAnswer
    let frames: [PvPFrame]
    let results: [PvPFilmResult]
}

struct PvPFinished: Codable, Sendable, Equatable {
    let reason: PvPFinishReason
    let winnerUid: String?
    let standings: [PvPStanding]
    let films: [PvPFinishedFilm]
}

struct PvPPrepare: Codable, Sendable, Equatable {
    let film: Int
    let total: Int
    let frames: [PvPFrame]
    let spares: [PvPFrame]
    let ready: Bool?
}

// MARK: - Snapshot

struct PvPSnapshot: Codable, Sendable, Equatable {
    struct Film: Codable, Sendable, Equatable {
        let index: Int
        let total: Int
        let progress: [PvPProgress]
        let startsInMs: Int
        let endsInMs: Int
        let frames: [PvPFrame]?
        let spares: [PvPFrame]?
        let yourFrame: Int?
        let yourStatus: PvPFilmStatus?
    }

    struct Paused: Codable, Sendable, Equatable {
        let remainingMs: Int
        let autoResumeInMs: Int
    }

    let seq: Int
    let phase: PvPPhase
    let code: String
    let you: String
    let hostUid: String?
    let settings: PvPSettings
    let players: [PvPPlayer]
    let film: Film?
    let prepare: PvPPrepare?
    let paused: Paused?
    let standings: [PvPStanding]
    let lastReveal: PvPReveal?
    let finished: PvPFinished?
    let duel: PvPDuelState?
}

// MARK: - Server messages

struct PvPWelcome: Codable, Sendable, Equatable {
    struct You: Codable, Sendable, Equatable {
        let uid: String
        let resumeToken: String
    }

    let seq: Int
    let you: You
    let snapshot: PvPSnapshot?
}

struct PvPPoll: Decodable, Sendable {
    let messages: [PvPEnvelope]
}

enum PvPServerMessage: Decodable, Sendable, Equatable {
    case welcome(PvPWelcome)
    case snapshot(PvPSnapshot)
    case player(PvPPlayer)
    case playerRemoved(uid: String, reason: String)
    case settings(PvPSettings)
    case loading
    case prepare(PvPPrepare)
    case countdown(film: Int, startsInMs: Int, timeLimitMs: Int, participants: [String])
    case progress(film: Int, PvPProgress)
    case guessResult(film: Int, frame: Int, correct: Bool)
    case deadline(film: Int, endsInMs: Int)
    case paused(PvPSnapshot.Paused)
    case resumed(startsInMs: Int)
    case reveal(PvPReveal)
    case finished(PvPFinished)
    case error(code: String, message: String)
    case pong
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case t, player, uid, reason, settings, film, startsInMs, timeLimitMs, participants
        case frame, correct, endsInMs, code, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .t)
        switch type {
        case "welcome":
            self = .welcome(try PvPWelcome(from: decoder))
        case "snapshot":
            self = .snapshot(try PvPSnapshot(from: decoder))
        case "player":
            self = .player(try container.decode(PvPPlayer.self, forKey: .player))
        case "playerRemoved":
            self = .playerRemoved(uid: try container.decode(String.self, forKey: .uid), reason: try container.decode(String.self, forKey: .reason))
        case "settings":
            self = .settings(try container.decode(PvPSettings.self, forKey: .settings))
        case "loading":
            self = .loading
        case "prepare":
            self = .prepare(try PvPPrepare(from: decoder))
        case "countdown":
            self = .countdown(
                film: try container.decode(Int.self, forKey: .film),
                startsInMs: try container.decode(Int.self, forKey: .startsInMs),
                timeLimitMs: try container.decode(Int.self, forKey: .timeLimitMs),
                participants: try container.decode([String].self, forKey: .participants)
            )
        case "progress":
            self = .progress(film: try container.decode(Int.self, forKey: .film), try PvPProgress(from: decoder))
        case "guessResult":
            self = .guessResult(
                film: try container.decode(Int.self, forKey: .film),
                frame: try container.decode(Int.self, forKey: .frame),
                correct: try container.decode(Bool.self, forKey: .correct)
            )
        case "deadline":
            self = .deadline(film: try container.decode(Int.self, forKey: .film), endsInMs: try container.decode(Int.self, forKey: .endsInMs))
        case "paused":
            self = .paused(try PvPSnapshot.Paused(from: decoder))
        case "resumed":
            self = .resumed(startsInMs: try container.decode(Int.self, forKey: .startsInMs))
        case "reveal":
            self = .reveal(try PvPReveal(from: decoder))
        case "finished":
            self = .finished(try PvPFinished(from: decoder))
        case "error":
            self = .error(code: try container.decode(String.self, forKey: .code), message: try container.decode(String.self, forKey: .message))
        case "pong":
            self = .pong
        default:
            self = .unknown(type)
        }
    }
}

struct PvPEnvelope: Decodable, Sendable, Equatable {
    let seq: Int?
    let message: PvPServerMessage

    init(seq: Int?, message: PvPServerMessage) {
        self.seq = seq
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case seq
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decodeIfPresent(Int.self, forKey: .seq)
        message = try PvPServerMessage(from: decoder)
    }
}

// MARK: - Client messages

enum PvPClientMessage: Encodable, Sendable, Equatable {
    case ping
    case ready(film: Int)
    case unready
    case guess(film: Int, frame: Int, tmdbId: Int?, mediaType: MediaType, text: String? = nil)
    case skip(film: Int, frame: Int)
    case frameBroken(film: Int, index: Int)
    case away(Bool)
    case leave
    case settings(films: Int?, frames: Int?, timeLimitSec: Int?)
    case start
    case pause
    case resume
    case kick(uid: String)
    case hideName(uid: String)
    case newMatch

    private enum CodingKeys: String, CodingKey {
        case t, film, frame, tmdbId, mediaType, text, index, away, films, frames, timeLimitSec, uid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ping:
            try container.encode("ping", forKey: .t)
        case .ready(let film):
            try container.encode("ready", forKey: .t)
            try container.encode(film, forKey: .film)
        case .unready:
            try container.encode("unready", forKey: .t)
        case .guess(let film, let frame, let tmdbId, let mediaType, let text):
            try container.encode("guess", forKey: .t)
            try container.encode(film, forKey: .film)
            try container.encode(frame, forKey: .frame)
            try container.encodeIfPresent(tmdbId, forKey: .tmdbId)
            try container.encode(mediaType, forKey: .mediaType)
            try container.encodeIfPresent(text, forKey: .text)
        case .skip(let film, let frame):
            try container.encode("skip", forKey: .t)
            try container.encode(film, forKey: .film)
            try container.encode(frame, forKey: .frame)
        case .frameBroken(let film, let index):
            try container.encode("frameBroken", forKey: .t)
            try container.encode(film, forKey: .film)
            try container.encode(index, forKey: .index)
        case .away(let away):
            try container.encode("away", forKey: .t)
            try container.encode(away, forKey: .away)
        case .leave:
            try container.encode("leave", forKey: .t)
        case .settings(let films, let frames, let timeLimitSec):
            try container.encode("settings", forKey: .t)
            try container.encodeIfPresent(films, forKey: .films)
            try container.encodeIfPresent(frames, forKey: .frames)
            try container.encodeIfPresent(timeLimitSec, forKey: .timeLimitSec)
        case .start:
            try container.encode("start", forKey: .t)
        case .pause:
            try container.encode("pause", forKey: .t)
        case .resume:
            try container.encode("resume", forKey: .t)
        case .kick(let uid):
            try container.encode("kick", forKey: .t)
            try container.encode(uid, forKey: .uid)
        case .hideName(let uid):
            try container.encode("hideName", forKey: .t)
            try container.encode(uid, forKey: .uid)
        case .newMatch:
            try container.encode("newMatch", forKey: .t)
        }
    }
}

struct PvPPollRequest: Encodable, Sendable {
    let lastSeq: Int
    let send: [PvPClientMessage]
}
