import Foundation
import Testing
@testable import PvPScreen

private typealias F = PvPMatchFixtures

private func screen(_ state: PvPMatchState, now: Date = Date(), options: PvPScreenOptions = PvPScreenOptions()) -> PvPScreen {
    PvPScreen(state: state, now: now, options: options)
}

private func lobby(_ state: PvPMatchState, options: PvPScreenOptions = PvPScreenOptions()) -> PvPLobbyScreen? {
    if case let .lobby(lobby) = screen(state, options: options).content { return lobby }
    return nil
}

private func match(_ state: PvPMatchState, now: Date = Date()) -> PvPMatchScreen? {
    if case let .match(match) = screen(state, now: now).content { return match }
    return nil
}

private func reveal(_ state: PvPMatchState) -> PvPRevealScreen? {
    if case let .reveal(reveal) = screen(state).content { return reveal }
    return nil
}

private func final(_ state: PvPMatchState, options: PvPScreenOptions = PvPScreenOptions()) -> PvPFinalScreen? {
    if case let .final(final) = screen(state, options: options).content { return final }
    return nil
}

struct PvPScreenTextTests {
    @Test func clocks() {
        #expect(PvPScreenText.clock(12) == "0:12")
        #expect(PvPScreenText.clock(11.2) == "0:12")
        #expect(PvPScreenText.clock(65) == "1:05")
        #expect(PvPScreenText.clock(0) == "0:00")
        #expect(PvPScreenText.clock(-3) == "0:00")
        #expect(PvPScreenText.clock(288) == "4:48")
    }

    @Test func numbers() {
        #expect(PvPScreenText.number(0) == "0")
        #expect(PvPScreenText.number(811) == "811")
        #expect(PvPScreenText.number(1720) == "1\u{202F}720")
        #expect(PvPScreenText.number(1_000_000) == "1\u{202F}000\u{202F}000")
        #expect(PvPScreenText.signed(811) == "+811")
        #expect(PvPScreenText.signed(0) == "0")
        #expect(PvPScreenText.damage(658) == "−658")
        #expect(PvPScreenText.seconds(milliseconds: 6200) == "6,2 с")
        #expect(PvPScreenText.seconds(milliseconds: 11849) == "11,8 с")
        #expect(PvPScreenText.multiplier(2) == "×2")
        #expect(PvPScreenText.multiplier(1.5) == "×1,5")
    }

    @Test func plurals() {
        #expect(PvPScreenText.frames(1) == "1 кадр")
        #expect(PvPScreenText.frames(3) == "3 кадра")
        #expect(PvPScreenText.frames(6) == "6 кадров")
        #expect(PvPScreenText.players(2) == "2 игрока")
        #expect(PvPScreenText.points(1) == "1 очко")
        #expect(PvPScreenText.films(5, mediaType: .movie) == "5 фильмов")
    }
}

struct PvPScreenContentTests {
    @Test func everyFixtureLandsOnAScreen() {
        for (name, state) in F.all {
            let content = screen(state).content
            switch state.phase {
            case .lobby: #expect({ if case .lobby = content { true } else { false } }(), "\(name)")
            case .loading, .ready, .countdown, .playing: #expect({ if case .match = content { true } else { false } }(), "\(name)")
            case .reveal: #expect({ if case .reveal = content { true } else { false } }(), "\(name)")
            case .finished: #expect({ if case .final = content { true } else { false } }(), "\(name)")
            case .closed: #expect({ if case .closed = content { true } else { false } }(), "\(name)")
            case .connecting: #expect({ if case .connecting = content { true } else { false } }(), "\(name)")
            }
        }
    }

    @Test func connectingWithoutSettings() {
        var state = PvPMatchState(code: "120934")
        state.phase = .lobby
        guard case let .connecting(connecting) = screen(state).content else { Issue.record("not connecting"); return }
        #expect(connecting.detail == "Код 120934")
    }
}

struct PvPLobbyScreenTests {
    @Test func hostSeesStartAndSettings() throws {
        let lobby = try #require(lobby(F.lobbyHost))
        #expect(lobby.primary == PvPAction(kind: .start, title: "Начать", isEnabled: true))
        #expect(lobby.settings.filter { $0.isEditable }.count == 3)
        #expect(lobby.settings.first { $0.field == .films }?.options.map(\.value) == [5, 10, 15])
        #expect(lobby.settings.first { $0.field == .timeLimit }?.selectedLabel == "30 с")
        #expect(lobby.players.first?.isYou == true)
        #expect(lobby.players.first?.status == "Хост")
        #expect(lobby.players.dropFirst().allSatisfy { $0.canKick && $0.canHideName })
        #expect(lobby.hint == "Готовы 1 из 3")
        #expect(lobby.seats == "4 из 8")
        #expect(lobby.summary == "5 фильмов · 6 кадров · 30 с на фильм")
    }

    @Test func guestTogglesReadyAndCannotEdit() throws {
        let lobby = try #require(lobby(F.lobbyGuest))
        #expect(lobby.primary.kind == .unready)
        #expect(lobby.settings.allSatisfy { !$0.isEditable })
        #expect(lobby.players.first?.uid == F.rival)
        #expect(lobby.players.first?.isHost == true)
        #expect(lobby.players.allSatisfy { !$0.canKick && !$0.canHideName })
        #expect(lobby.players.filter { !$0.isYou }.allSatisfy { $0.canHideForMe })
        #expect(lobby.hint == "Матч запускает хост")
        let away = try #require(lobby.players.first { $0.uid == F.fourth })
        #expect(away.tone == .away)
    }

    @Test func aloneHostCannotStart() throws {
        let lobby = try #require(lobby(F.lobbyAlone))
        #expect(lobby.primary.isEnabled == false)
        #expect(lobby.hint == "Нужен хотя бы ещё один игрок — отправьте код")
        #expect(screen(F.lobbyAlone).chrome.banners.contains { $0.kind == .notice && $0.title == "Нужно хотя бы два игрока" })
    }

    @Test func staleNoticeDisappears() {
        let later = Date().addingTimeInterval(PvPScreenBuilder.noticeLifetime + 1)
        #expect(screen(F.lobbyAlone, now: later).chrome.banners.isEmpty)
    }

    @Test func duelLobby() throws {
        let lobby = try #require(lobby(F.lobbyDuel))
        #expect(lobby.primary.kind == .ready)
        #expect(lobby.seats == "2 из 2")
        #expect(lobby.settings.map(\.field) == [.films, .frames, .timeLimit, .health])
        #expect(lobby.settings.first?.selectedLabel == "до 20")
        #expect(lobby.hint == "SilentFoley готов — дуэль начнётся, как только вы нажмёте «Готов»")
        #expect(lobby.players.allSatisfy { !$0.isHost && !$0.canKick })
        #expect(lobby.summary.hasPrefix("До победы"))
    }

    @Test func hiddenNameUsesAlias() throws {
        let lobby = try #require(lobby(F.lobbyGuest, options: PvPScreenOptions(hiddenNames: [F.third])))
        let row = try #require(lobby.players.first { $0.uid == F.third })
        #expect(row.name == "HiddenMidnig")
        #expect(row.isNameHidden)
    }

    @Test func seatsWithoutACountFromAnOldServer() throws {
        var state = F.lobbyHost
        state.settings = PvPSettings(kind: .room, mediaType: .movie, films: 5, frames: 6, timeLimitSec: 30, hp: nil, maxFilms: nil)
        let lobby = try #require(lobby(state))
        #expect(lobby.seats == "4 игрока")
    }

    @Test func fixtureCodesFitTheServerAlphabet() {
        for (name, state) in F.all {
            #expect(PvPRoomLink.isValid(state.code), "\(name): \(state.code)")
        }
    }

    @Test func lobbyLeaveNeedsNoConfirmation() {
        let leave = screen(F.lobbyHost).chrome.leave
        #expect(leave.kind == .leave)
        #expect(leave.confirmation == nil)
    }
}

struct PvPMatchScreenTests {
    @Test func picking() throws {
        let match = try #require(match(F.loading))
        #expect(match.stage == .picking)
        #expect(match.stageText == "Подбираем фильмы")
        #expect(match.input.isEnabled == false)
    }

    @Test func preparingAndWaiting() throws {
        let preparing = try #require(match(F.preparing))
        #expect(preparing.stage == .preparing)
        let waiting = try #require(match(F.preparedWaiting))
        #expect(waiting.stage == .waiting)
        #expect(waiting.stageText == "Ждём остальных")
        #expect(waiting.title == "Фильм 1 из 5")
        let duel = try #require(match(F.duelPreparing))
        #expect(duel.title == "Фильм 1")
    }

    @Test func countdown() throws {
        let match = try #require(match(F.countdown))
        #expect(match.stage == .countdown(3))
        #expect(match.frames.allSatisfy { !$0.isUnlocked })
        #expect(match.timer?.text == "0:30")
        #expect(match.timer?.isFrozen == true)
        #expect(match.input.isEnabled == false)
    }

    @Test func thinking() throws {
        let match = try #require(match(F.playingThinking))
        #expect(match.stage == .playing)
        #expect(match.title == "Фильм 2 из 5")
        #expect(match.frames.filter { $0.isUnlocked }.count == 2)
        #expect(match.shownFrame == 1)
        #expect(match.frameCaption == "Кадр 2 из 6")
        #expect(match.timer?.text == "0:22")
        #expect(match.timer?.isUrgent == false)
        #expect(match.input.isEnabled)
        #expect(match.status == PvPYourStatus(text: "Мимо — открыт кадр 2", tone: .wrong))
        #expect(match.rivals.map(\.uid) == [F.rival, F.third, F.fourth])
        #expect(match.rivals.first { $0.uid == F.third }?.status == "Кадр 3 из 6")
        #expect(match.rivals.first { $0.uid == F.fourth }?.tone == .out)
        #expect(match.rivals.first { $0.uid == F.fourth }?.isAway == true)
        #expect(match.isProtected)
        #expect(match.duel == nil)
    }

    @Test func sending() throws {
        let match = try #require(match(F.playingAnswering))
        #expect(match.input.isEnabled == false)
        #expect(match.input.isSending)
        #expect(match.status?.tone == .sending)
    }

    @Test func deadline() throws {
        let match = try #require(match(F.playingDeadline))
        #expect(match.timer?.isUrgent == true)
        #expect(match.timerNote != nil)
        #expect(match.rivals.first { $0.uid == F.rival }?.tone == .solved)
        #expect(match.rivals.first { $0.uid == F.third }?.tone == .failed)
        #expect(match.frameCaption == "Кадр 5 из 6")
    }

    @Test func solved() throws {
        let match = try #require(match(F.playingSolved))
        #expect(match.status == PvPYourStatus(text: "Верно! Угадали на 2-м кадре", tone: .solved))
        #expect(match.input.isEnabled == false)
        #expect(match.isProtected)
        #expect(match.viewableFrame == match.frames.count - 1)
        #expect(match.input.feedback == PvPMatchGuess(frame: 2, correct: true))
    }

    @Test func spectator() throws {
        let match = try #require(match(F.playingSpectator))
        #expect(match.stage == .watching)
        #expect(match.frames.isEmpty)
        #expect(match.input.isEnabled == false)
        #expect(match.isProtected == false)
        #expect(match.timer != nil)
    }

    @Test func duel() throws {
        let match = try #require(match(F.duelPlaying))
        #expect(match.title == "Фильм 5")
        let duel = try #require(match.duel)
        #expect(duel.you.uid == F.you)
        #expect(duel.you.text == "2\u{202F}140")
        #expect(duel.rival.hp == 1385)
        #expect(abs(duel.rival.fraction - 1385.0 / 3000) < 0.0001)
        #expect(duel.multiplier == "Урон ×2")
    }

    @Test func pausedFreezesEverything() throws {
        let state = F.paused
        let match = try #require(match(state))
        #expect(match.timer == PvPTimer(text: "0:18", fraction: 0.6, isUrgent: false, isFrozen: true))
        #expect(match.input.isEnabled == false)
        let chrome = screen(state).chrome
        #expect(chrome.canPause == false)
        #expect(chrome.canResume)
        #expect(chrome.pause?.detail == "Вы поставили игру на паузу")
        #expect(chrome.pause?.autoResume.hasPrefix("Продолжим сами через 4:4") == true)
    }

    @Test func guestSeesWhoPaused() {
        var state = F.paused
        state.players = F.roomPlayers(host: F.rival, ready: true)
        let chrome = screen(state).chrome
        #expect(chrome.pause?.detail == "SilentFoley поставил игру на паузу")
        #expect(chrome.pause?.canResume == false)
        #expect(chrome.canResume == false)
    }

    @Test func resuming() throws {
        let match = try #require(match(F.resuming))
        #expect(match.resumeIn == 3)
        #expect(match.input.isEnabled == false)
        #expect(match.timer?.isFrozen == true)
        #expect(match.timer?.text == "0:18")
    }

    @Test func hostCanPauseRunningRoom() {
        #expect(screen(F.playingThinking).chrome.canPause)
        #expect(screen(F.duelPlaying).chrome.canPause == false)
    }

    @Test func leavingMidMatch() {
        #expect(screen(F.playingThinking).chrome.leave.kind == .leave)
        #expect(screen(F.playingThinking).chrome.leave.confirmation?.contains(F.roomCode) == true)
        #expect(screen(F.duelPlaying).chrome.leave.kind == .forfeit)
    }
}

struct PvPBannerTests {
    @Test func rivalOffline() throws {
        let banners = screen(F.rivalOffline).chrome.banners
        let banner = try #require(banners.first { $0.kind == .rivalOffline })
        #expect(banner.title == "SilentFoley не в сети")
        #expect(banner.detail?.hasPrefix("Техническая победа через 0:4") == true)
        #expect(banner.isUrgent)
    }

    @Test func rivalAway() {
        #expect(screen(F.rivalAway).chrome.banners.contains { $0.kind == .rivalAway && $0.title == "SilentFoley свернул приложение" })
    }

    @Test func linkModes() {
        #expect(screen(F.polling).chrome.banners.contains { $0.kind == .polling })
        #expect(screen(F.reconnecting).chrome.banners.contains { $0.kind == .reconnecting })
        #expect(screen(F.playingThinking).chrome.banners.isEmpty)
    }

    @Test func noForfeitBannersAfterTheMatch() {
        #expect(screen(F.finishedForfeitVictory).chrome.banners.isEmpty)
    }
}

struct PvPRevealScreenTests {
    @Test func room() throws {
        let reveal = try #require(reveal(F.revealRoom))
        #expect(reveal.title == "Фильм 2 из 5")
        #expect(reveal.answer == PvPAnswerCard(title: "Матрица", subtitle: "The Matrix · 1999", posterPath: "/fixture-poster-1.jpg"))
        #expect(reveal.verdict == "Вы угадали на 2-м кадре · +811")
        #expect(reveal.isSolved)
        #expect(reveal.results.map(\.uid) == [F.rival, F.you, F.third])
        #expect(reveal.results.first?.detail == "кадр 1 · 6,2 с")
        #expect(reveal.results.last?.points == "0")
        #expect(reveal.standings.map(\.place) == [1, 2, 3, 4])
        #expect(reveal.standings.first?.score == "1\u{202F}720")
        #expect(reveal.duel == nil)
        #expect(reveal.next == "Следующий фильм")
        #expect(reveal.nextTimer?.text == "0:06")
    }

    @Test func duel() throws {
        let reveal = try #require(reveal(F.revealDuel))
        #expect(reveal.title == "Фильм 5")
        #expect(reveal.standings.isEmpty)
        #expect(reveal.duel?.rival.damage == "−658")
        #expect(reveal.duel?.you.damage == nil)
        #expect(reveal.damageLine == "SilentFoley получает 658 урона · ×2")
    }
}

struct PvPFinalScreenTests {
    @Test func outcomes() throws {
        let cases: [(PvPMatchState, String, PvPFinalScreen.Tone)] = [
            (F.finishedVictory, "Победа", .win),
            (F.finishedDefeat, "Поражение", .loss),
            (F.finishedForfeitVictory, "Победа", .win),
            (F.finishedForfeitDefeat, "Техническое поражение", .loss),
            (F.finishedDraw, "Ничья", .draw),
            (F.finishedAbandoned, "Матч не состоялся", .neutral),
            (F.finishedRoom, "2-е место", .neutral),
            (F.finishedRoomWinner, "1-е место", .win)
        ]
        for (state, title, tone) in cases {
            let final = try #require(final(state))
            #expect(final.title == title)
            #expect(final.tone == tone)
        }
        let forfeit = try #require(final(F.finishedForfeitVictory))
        #expect(forfeit.subtitle.hasPrefix("Техническая"))
        let knockout = try #require(final(F.finishedVictory))
        #expect(knockout.subtitle == "У соперника кончилось здоровье")
    }

    @Test func roomTable() throws {
        let final = try #require(final(F.finishedRoom))
        #expect(final.standings.map(\.uid) == [F.rival, F.you, F.third, F.fourth])
        #expect(final.standings[1].isYou)
        #expect(final.subtitle == "из 4 · 3\u{202F}610 очков")
        #expect(final.films.count == 3)
        #expect(final.films.first?.yourResult == "кадр 1 · +900")
        #expect(final.solvedLine == "Угадано 3 из 3")
        #expect(final.primary == PvPAction(kind: .newMatch, title: "Новый матч", isEnabled: true))
        #expect(final.shareText.hasPrefix("Franamed · Комната · 2-е место"))
        #expect(final.shareText.contains("Угадано 3 из 3: 1 2 3"))
    }

    @Test func roomGuestWaitsForHost() throws {
        var state = F.finishedRoom
        state.players = F.roomPlayers(host: F.rival)
        let final = try #require(final(state))
        #expect(final.primary == nil)
        #expect(final.hint == "Новый матч запускает хост")
    }

    @Test func duelRematch() throws {
        let state = F.finishedVictory
        let fresh = try #require(final(state))
        #expect(fresh.primary == PvPAction(kind: .newMatch, title: "Ещё раз", isEnabled: true))
        #expect(fresh.standings.first?.score == "1\u{202F}210 HP")
        let asked = try #require(final(state, options: PvPScreenOptions(newMatchRequestedFor: state.result?.id)))
        #expect(asked.primary == PvPAction(kind: .newMatch, title: "Ждём соперника", isEnabled: false))
        let gone = try #require(final(F.finishedForfeitVictory))
        #expect(gone.primary?.isEnabled == false)
        #expect(gone.hint == "Соперник ушёл")
    }

    @Test func drawSharesPlace() throws {
        let final = try #require(final(F.finishedDraw))
        #expect(final.standings.allSatisfy { $0.place == 1 && $0.isTied })
    }

    @Test func finishedClosesWithoutConfirmation() {
        #expect(screen(F.finishedRoom).chrome.leave.kind == .close)
    }
}

struct PvPClosedScreenTests {
    @Test func closures() throws {
        guard case let .closed(kicked) = screen(F.kicked).content else { Issue.record("not closed"); return }
        #expect(kicked.kind == .kicked)
        #expect(kicked.action == nil)
        guard case let .closed(gone) = screen(F.roomGone).content else { Issue.record("not closed"); return }
        #expect(gone.kind == .roomGone)
        #expect(gone.message == "Комнаты с таким кодом нет. Проверьте код")
        var dropped = F.playingThinking
        dropped.phase = .closed(.disconnected)
        guard case let .closed(lost) = screen(dropped).content else { Issue.record("not closed"); return }
        #expect(lost.action?.kind == .reconnect)
    }
}

struct PvPProfileRulesTests {
    @Test func names() {
        #expect(PvPProfileRules.check(name: "NoirGaffer") == .valid)
        #expect(PvPProfileRules.check(name: "ab") == .tooShort)
        #expect(PvPProfileRules.check(name: "abcdefghijklmnopq") == .tooLong)
        #expect(PvPProfileRules.check(name: "Нуар") == .badCharacters)
        #expect(PvPProfileRules.check(name: "no space") == .badCharacters)
        #expect(PvPProfileRules.check(name: "snake_case_9") == .valid)
    }
}
