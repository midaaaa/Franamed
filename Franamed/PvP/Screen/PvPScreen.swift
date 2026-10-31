//
//  PvPScreen.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Foundation

// MARK: - Screen

struct PvPScreenOptions: Sendable, Equatable {
    var hiddenNames: Set<String> = []
    var newMatchRequestedFor: String?
}

struct PvPScreen: Sendable, Equatable {
    enum Content: Sendable, Equatable {
        case connecting(PvPConnectingScreen)
        case lobby(PvPLobbyScreen)
        case match(PvPMatchScreen)
        case reveal(PvPRevealScreen)
        case final(PvPFinalScreen)
        case closed(PvPClosedScreen)
    }

    let content: Content
    let chrome: PvPChrome

    init(state: PvPMatchState, now: Date, options: PvPScreenOptions = PvPScreenOptions()) {
        let builder = PvPScreenBuilder(state: state, now: now, options: options)
        content = builder.content()
        chrome = builder.chrome()
    }
}

// MARK: - Chrome

struct PvPChrome: Sendable, Equatable {
    let title: String
    let code: String
    let banners: [PvPBanner]
    let canPause: Bool
    let canResume: Bool
    let leave: PvPLeave
    let pause: PvPPauseOverlay?
    let isAway: Bool
}

struct PvPLeave: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case close
        case leave
        case forfeit
    }

    let kind: Kind
    let title: String
    let confirmation: String?
    let confirmTitle: String
}

struct PvPBanner: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        case reconnecting
        case polling
        case rivalOffline
        case rivalAway
        case notice
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String?
    let isUrgent: Bool
}

struct PvPPauseOverlay: Sendable, Equatable {
    let title: String
    let detail: String
    let autoResume: String
    let canResume: Bool
}

// MARK: - Shared rows

struct PvPAvatar: Sendable, Equatable {
    let icon: String
    let color: String
}

struct PvPAction: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case ready
        case unready
        case start
        case newMatch
        case reconnect
    }

    let kind: Kind
    let title: String
    let isEnabled: Bool
}

struct PvPTimer: Sendable, Equatable {
    let text: String
    let fraction: Double
    let isUrgent: Bool
    let isFrozen: Bool
}

struct PvPStandingRow: Sendable, Equatable, Identifiable {
    let uid: String
    let place: Int
    let isTied: Bool
    let name: String
    let avatar: PvPAvatar
    let isYou: Bool
    let score: String
    let detail: String?
    let isOut: Bool

    var id: String { uid }
}

struct PvPHealthBar: Sendable, Equatable, Identifiable {
    let uid: String
    let name: String
    let avatar: PvPAvatar
    let isYou: Bool
    let hp: Int
    let maxHP: Int
    let text: String
    let damage: String?

    var id: String { uid }

    var fraction: Double { maxHP > 0 ? min(1, max(0, Double(hp) / Double(maxHP))) : 0 }
}

struct PvPDuelBars: Sendable, Equatable {
    let you: PvPHealthBar
    let rival: PvPHealthBar
    let multiplier: String?
}

// MARK: - Connecting and closed

struct PvPConnectingScreen: Sendable, Equatable {
    let title: String
    let detail: String
}

struct PvPClosedScreen: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case disconnected
        case left
        case replaced
        case kicked
        case roomGone
        case refused
        case failed
    }

    let kind: Kind
    let title: String
    let message: String
    let action: PvPAction?
}
