//
//  PvPMatchViewModel.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import Combine
import Foundation

@MainActor
final class PvPMatchViewModel: ObservableObject {
    @Published private(set) var state: PvPMatchState
    @Published private(set) var options = PvPScreenOptions()

    private let session: any PvPSessionProtocol

    init(session: any PvPSessionProtocol, code: String) {
        self.session = session
        self.state = PvPMatchState(code: code)
    }

    func screen(at now: Date) -> PvPScreen {
        PvPScreen(state: state, now: now, options: options)
    }

    func run() async {
        let session = session
        Task { await session.connect() }
        for await next in session.states() {
            state = next
        }
    }

    // MARK: Actions

    func perform(_ action: PvPAction.Kind) {
        switch action {
        case .ready: send { await $0.ready() }
        case .unready: send { await $0.unready() }
        case .start: send { await $0.start() }
        case .newMatch:
            options.newMatchRequestedFor = state.result?.id
            send { await $0.newMatch() }
        case .reconnect: send { await $0.connect() }
        }
    }

    func guess(_ item: MediaItem?, text: String, mediaType: MediaType) {
        send { await $0.guess(tmdbId: item?.id, mediaType: item?.mediaType ?? mediaType, text: text) }
    }

    func skip() { send { await $0.skip() } }
    func pause() { send { await $0.pause() } }
    func resume() { send { await $0.resume() } }
    func kick(_ uid: String) { send { await $0.kick(uid: uid) } }
    func hideName(_ uid: String) { send { await $0.hideName(uid: uid) } }
    func setAway(_ away: Bool) { send { await $0.setAway(away) } }

    func toggleHiddenName(_ uid: String) {
        if options.hiddenNames.contains(uid) {
            options.hiddenNames.remove(uid)
        } else {
            options.hiddenNames.insert(uid)
        }
    }

    func change(_ field: PvPSettingRow.Field, to value: Int) {
        switch field {
        case .films: send { await $0.changeSettings(films: value, frames: nil, timeLimitSec: nil) }
        case .frames: send { await $0.changeSettings(films: nil, frames: value, timeLimitSec: nil) }
        case .timeLimit: send { await $0.changeSettings(films: nil, frames: nil, timeLimitSec: value) }
        case .health: break
        }
    }

    func leave(_ kind: PvPLeave.Kind) async {
        if kind != .close { await session.leave() }
        await session.disconnect()
    }

    private func send(_ action: @escaping @Sendable (any PvPSessionProtocol) async -> Void) {
        let session = session
        Task { await action(session) }
    }
}
