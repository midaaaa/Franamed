//
//  PvPTicketView.swift
//  Franamed
//
//  Created by Claude on 20.11.2026.
//

import SwiftUI
import UIKit

/// The PvP ticket on the main screen. Empty, it is a Room or Duel ticket (tap the title to turn it over);
/// inside a room it becomes the lobby: seats fill with players, the stub carries the room code,
/// and tearing the stub off means "ready".
struct PvPTicketView: View {
    @ObservedObject var model: PvPTicketModel
    let mediaType: MediaType
    let width: CGFloat
    let posterHeight: CGFloat
    let edgeStyle: TicketEdgeStyle

    var body: some View {
        if let room = model.room {
            PvPTicketLiveCard(model: model, room: room, mediaType: mediaType, width: width,
                              posterHeight: posterHeight, edgeStyle: edgeStyle)
        } else {
            PvPTicketCard(model: model, lobby: nil, room: nil, mediaType: mediaType, width: width,
                          posterHeight: posterHeight, edgeStyle: edgeStyle)
        }
    }
}

/// Re-renders the ticket whenever the room's state changes.
private struct PvPTicketLiveCard: View {
    @ObservedObject var model: PvPTicketModel
    @ObservedObject var room: PvPMatchViewModel
    let mediaType: MediaType
    let width: CGFloat
    let posterHeight: CGFloat
    let edgeStyle: TicketEdgeStyle

    var body: some View {
        let screen = room.screen(at: .now)
        let lobby: PvPLobbyScreen? = if case let .lobby(lobby) = screen.content { lobby } else { nil }
        PvPTicketCard(model: model, lobby: lobby, room: room, mediaType: room.state.settings?.mediaType ?? mediaType,
                      width: width, posterHeight: posterHeight, edgeStyle: edgeStyle)
    }
}

// MARK: - Card

private struct PvPTicketCard: View {
    @ObservedObject var model: PvPTicketModel
    let lobby: PvPLobbyScreen?
    let room: PvPMatchViewModel?
    let mediaType: MediaType
    let width: CGFloat
    let posterHeight: CGFloat
    let edgeStyle: TicketEdgeStyle

    @State private var angle: Double
    @State private var isEditingProfile = false
    @AppStorage(PvPTicketStyle.mosaicKey) private var hasMosaic = true

    init(model: PvPTicketModel, lobby: PvPLobbyScreen?, room: PvPMatchViewModel?, mediaType: MediaType,
         width: CGFloat, posterHeight: CGFloat, edgeStyle: TicketEdgeStyle) {
        self.model = model
        self.lobby = lobby
        self.room = room
        self.mediaType = mediaType
        self.width = width
        self.posterHeight = posterHeight
        self.edgeStyle = edgeStyle
        // Start on the right side: swiping in from another ticket mode must not turn the card over.
        let kind = lobby?.kind ?? room?.state.kind ?? model.kind
        _angle = State(initialValue: kind == .duel ? 180 : 0)
    }

    private var stubHeight: CGFloat { TicketStubMetrics.height(width: width, edgeStyle: edgeStyle) }
    private var zoom: CGFloat { TicketStyle.zoom(forWidth: width) }

    /// The kind on show: the room's own kind once inside, the chosen one before.
    private var kind: PvPRoomKind { lobby?.kind ?? room?.state.kind ?? model.kind }

    var body: some View {
        Group {
            if room == nil {
                PvPTicketFlip(angle: angle, size: CGSize(width: width, height: posterHeight + stubHeight),
                              notch: (posterHeight, TicketStyle.notchRadius(forWidth: width))) {
                    face(.room)
                } back: {
                    face(.duel)
                }
            } else {
                face(kind)
            }
        }
        .onChange(of: kind) { _, kind in
            // Only a Room ↔ Duel change turns the ticket; anything else snaps without a flip.
            let target: Double = kind == .duel ? 180 : 0
            guard angle != target else { return }
            withAnimation(PvPTicketStyle.flip) { angle = target }
        }
        .task { await model.loadProfile() }
        .alert("Не получилось", isPresented: hasError) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.error ?? "")
        }
        .alert(closureTitle, isPresented: hasClosure) {
            Button("OK", role: .cancel) { model.close() }
        } message: {
            Text(closureMessage)
        }
        .sheet(isPresented: $isEditingProfile) {
            if let profile = model.profile {
                PvPProfileEditor(profile: profile, isSaving: model.busy == .saving) { update in
                    await model.update(update)
                }
            }
        }
    }

    private var hasError: Binding<Bool> {
        Binding { model.error != nil } set: { if !$0 { model.dismissError() } }
    }

    private var hasClosure: Binding<Bool> {
        Binding { model.closure != nil && !model.isInMatch } set: { if !$0 { model.close() } }
    }

    private var closureTitle: String {
        guard let closure = model.closure else { return "" }
        return PvPScreen(state: closedState(closure), now: .now).closedTitle ?? "Комната закрыта"
    }

    private var closureMessage: String {
        guard let closure = model.closure else { return "" }
        return PvPScreen(state: closedState(closure), now: .now).closedMessage ?? ""
    }

    private func closedState(_ closure: PvPMatchClosure) -> PvPMatchState {
        var state = room?.state ?? PvPMatchState(code: model.code)
        state.phase = .closed(closure)
        return state
    }

    // MARK: Face

    private func face(_ side: PvPRoomKind) -> some View {
        let shown = room == nil ? side : kind
        return PvPTicketFace(
            kind: shown,
            lobby: lobby,
            isConnecting: room != nil && lobby == nil,
            mediaType: mediaType,
            width: width,
            posterHeight: posterHeight,
            stubHeight: stubHeight,
            edgeStyle: edgeStyle,
            hasMosaic: hasMosaic,
            settings: settings,
            model: model,
            onFlip: flip,
            onChange: { room?.change($0, to: $1) },
            onEditProfile: { isEditingProfile = true },
            onAction: { room?.perform($0) },
            onPlayer: player,
            onLeave: { Task { await model.leave() } },
            onCreate: { Task { await model.create(mediaType: mediaType) } }
        )
    }

    private var settings: PvPTicketSettings {
        if let lobby {
            func value(_ field: PvPSettingRow.Field) -> PvPSettingRow? { lobby.settings.first { $0.field == field } }
            return PvPTicketSettings(films: value(.films), frames: value(.frames), timeLimit: value(.timeLimit))
        }
        func row(_ field: PvPSettingRow.Field, _ title: String, _ values: [Int], _ selected: Int, _ label: (Int) -> String) -> PvPSettingRow {
            PvPSettingRow(field: field, title: title, options: values.map { .init(value: $0, label: label($0)) },
                          selected: selected, isEditable: true)
        }
        return PvPTicketSettings(
            films: kind == .room ? row(.films, "Фильмов", PvPRoomChoices.films, model.films) { "\($0)" } : nil,
            frames: row(.frames, "Кадров", PvPRoomChoices.frames, model.frames) { "\($0)" },
            timeLimit: row(.timeLimit, "Время", PvPRoomChoices.timeLimits, model.timeLimit) { "\($0) с" }
        )
    }

    private func flip() {
        guard room == nil else { return }
        Haptics.shared.play(.menuSelect)
        model.kind = model.kind == .room ? .duel : .room
    }

    private func player(_ action: PvPPlayerAction, _ uid: String) {
        switch action {
        case .kick: room?.kick(uid)
        case .hideName: room?.hideName(uid)
        case .toggleHidden: room?.toggleHiddenName(uid)
        }
    }
}

enum PvPPlayerAction {
    case kick
    case hideName
    case toggleHidden
}

/// Keeps the hidden stub in the tear engine's snapshot, so a returning stub isn't blank.
private struct PvPStubHider: ViewModifier {
    let isHidden: Bool
    @Environment(\.ticketStubIsSnapshot) private var isSnapshot

    func body(content: Content) -> some View {
        content.opacity(isHidden && !isSnapshot ? 0 : 1)
    }
}

/// How hard the stub resists the finger. Switch in the ticket's pencil menu (debug builds).
enum PvPTearFeel: String, CaseIterable, Identifiable {
    case soft, game, snappy

    static let storageKey = "pvpTearFeel"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: "Мягко, тянется дольше"
        case .game: "Как в других режимах"
        case .snappy: "Резко, рвётся быстро"
        }
    }

    func apply(to config: inout TicketTearConfig) {
        switch self {
        case .soft:
            config.tearGain = 0.75
            config.breakStretch = 0.75
            config.creepFraction = 0.8
        case .game:
            break
        case .snappy:
            config.tearGain = 1.5
            config.breakStretch = 0.42
            config.creepFraction = 0.5
            config.stretchScale = 0.3
        }
    }
}

struct PvPTicketSettings {
    let films: PvPSettingRow?
    let frames: PvPSettingRow?
    let timeLimit: PvPSettingRow?
}

enum PvPTicketStyle {
    static let mosaicKey = "pvpTicketGuilloche"
    static let flip = Animation.spring(duration: 0.75, bounce: 0.18)
    /// The same dark grey as the playlist ticket.
    static let paper = TicketInk.print.paper
    static let edge = Color(white: 0.2)
    static let mono = Font.system(size: 9, weight: .semibold, design: .monospaced)
    static let label = Font.system(size: 7.5, weight: .heavy)
    static let codeDigit = Font.system(size: 24, weight: .semibold, design: .monospaced)

    /// Building the mosaic pipeline takes about half a second on first use, so do it before the ticket shows.
    static func prepareShaders() async {
        try? await ShaderLibrary.pvpGuilloche(.float2(1, 1), .float2(0, 0), .float(0)).compile(as: .colorEffect)
    }
}

private extension PvPScreen {
    var closedTitle: String? { if case let .closed(closed) = content { closed.title } else { nil } }
    var closedMessage: String? { if case let .closed(closed) = content { closed.message } else { nil } }
}

// MARK: - Face

private struct PvPTicketFace: View {
    let kind: PvPRoomKind
    let lobby: PvPLobbyScreen?
    let isConnecting: Bool
    let mediaType: MediaType
    let width: CGFloat
    let posterHeight: CGFloat
    let stubHeight: CGFloat
    let edgeStyle: TicketEdgeStyle
    let hasMosaic: Bool
    let settings: PvPTicketSettings
    @ObservedObject var model: PvPTicketModel
    let onFlip: () -> Void
    let onChange: (PvPSettingRow.Field, Int) -> Void
    let onEditProfile: () -> Void
    let onAction: (PvPAction.Kind) -> Void
    let onPlayer: (PvPPlayerAction, String) -> Void
    let onLeave: () -> Void
    let onCreate: () -> Void

    @State private var returnToken = 0
    @AppStorage(PvPTearFeel.storageKey) private var tearFeel = PvPTearFeel.game.rawValue
    @State private var isCopied = false

    private var zoom: CGFloat { TicketStyle.zoom(forWidth: width) }
    private var designPosterHeight: CGFloat { posterHeight / zoom }
    private var ink: TicketInk { .stub(for: mediaType) }

    /// You tore the stub: ready (guests) — the host's tear starts the match instead.
    private var isTorn: Bool { lobby?.primary.kind == .unready }

    private var shape: TicketPerforationShape {
        var config = TicketTearConfig.ticket(width: width)
        config.stubExtent = stubHeight
        return TicketPerforationShape(tearLineOffset: posterHeight,
                                      tearLineSlots: TearPerforation(config: config, length: width),
                                      edgeStyle: edgeStyle,
                                      designSize: CGSize(width: width, height: posterHeight + stubHeight))
    }

    var body: some View {
        if let lobby {
            tearable(lobby)
        } else {
            card(hidesStub: false)
        }
    }

    private func card(hidesStub: Bool) -> some View {
        ZStack(alignment: .top) {
            poster
                .frame(width: width, height: posterHeight)
                .mask(alignment: .top) {
                    shape.frame(width: width, height: posterHeight + stubHeight)
                        .frame(width: width, height: posterHeight, alignment: .top)
                        .clipped()
                }
            stubPaper
                .mask(alignment: .top) {
                    shape.frame(width: width, height: posterHeight + stubHeight)
                        .offset(y: -posterHeight)
                        .frame(width: width, height: stubHeight, alignment: .top)
                        .clipped()
                }
                .modifier(PvPStubHider(isHidden: hidesStub))
                .offset(y: posterHeight)
        }
        .frame(width: width, height: posterHeight + stubHeight, alignment: .top)
    }

    private var stubPaper: some View {
        stub
            .frame(width: width, height: stubHeight)
            .background(ink.paper)
            .environment(\.ticketInk, ink)
            .foregroundStyle(ink.ink)
    }

    // MARK: Tear

    private var tearEdge: TearEdge { TearEdge(seed: UInt64(lobby?.code ?? "") ?? 7) }

    private var tearConfig: TicketTearConfig {
        var config = TicketTearConfig.ticket(width: width)
        config.stubExtent = stubHeight
        config.edge = tearEdge
        config.backColor = ink.paper
        config.detachFlightDistance = 36 * zoom
        config.detachFlightDuration = 0.36
        config.detachFadeFraction = 0.7
        PvPTearFeel(rawValue: tearFeel)?.apply(to: &config)
        return config
    }

    private func contentID(_ lobby: PvPLobbyScreen) -> String {
        lobby.players.map { "\($0.uid)\($0.tone)\($0.name)" }.joined() + "\(lobby.primary.kind)\(hasMosaic)\(lobby.settings.map(\.selected))"
    }

    /// Inside a room the stub tears off along its real perforation, like in the other modes.
    /// Torn means ready: the stub stays just below the ticket; tap it to put it back.
    private func tearable(_ lobby: PvPLobbyScreen) -> some View {
        TicketTear(config: tearConfig, stubShape: ResultStubShape(edgeStyle: edgeStyle, edge: tearEdge),
                   contentID: contentID(lobby), isGrabEnabled: !isTorn && lobby.primary.isEnabled,
                   returnToken: returnToken, onComplete: { tear(lobby) }) {
            card(hidesStub: isTorn)
        }
        .overlay(alignment: .top) {
            if isTorn {
                Button {
                    Haptics.shared.play(.tabHeal)
                    onAction(.unready)
                } label: {
                    stubPaper
                        .mask { ResultStubShape(edgeStyle: edgeStyle, edge: tearEdge) }
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .offset(y: posterHeight + Self.readyDrop * zoom)
                .transition(.offset(y: -Self.readyDrop * zoom).combined(with: .opacity))
                .accessibilityLabel("Готов. Вернуть корешок")
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.25), value: isTorn)
        .onChange(of: isTorn) { old, new in
            if old, !new { returnToken &+= 1 }
        }
    }

    private static let readyDrop: CGFloat = 22

    // MARK: Poster

    private var poster: some View {
        ZStack {
            PvPTicketBackground(isMosaic: hasMosaic)
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                Spacer(minLength: 8)
                Group {
                    if kind == .duel { duelSeats } else { roomSeats }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 8)
                settingsRow
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .foregroundStyle(.white)
            .frame(width: TicketStyle.referenceWidth, height: designPosterHeight)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: width, height: posterHeight, alignment: .topLeading)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if lobby == nil, !isConnecting {
                    Button(action: onFlip) {
                        HStack(spacing: 8) {
                            title
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 20, height: 20)
                                .overlay { Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Перевернуть билет")
                } else {
                    title
                }
                if lobby == nil {
                    Text(kind == .duel ? "Ровно два игрока" : "2–8 игроков · правила задаёт хост")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 8)
            if lobby != nil || isConnecting {
                Menu {
                    Section(kind == .duel ? "Выйти из дуэли?" : "Выйти из комнаты?") {
                        Button("Выйти", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: onLeave)
                    }
                } label: {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .foregroundStyle(.white)
            }
        }
    }

    private var title: some View {
        Text(kind == .duel ? "Дуэль" : "Комната")
            .font(.system(size: 26, weight: .heavy))
    }

    // MARK: Seats

    private var seatedPlayers: [PvPPlayerRow] {
        (lobby?.players ?? []).filter { $0.tone != .left }
    }

    private var roomSeats: some View {
        let players = seatedPlayers
        return Grid(horizontalSpacing: 10, verticalSpacing: 12) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<4, id: \.self) { column in
                        let index = row * 4 + column
                        PvPTicketSeat(number: index + 1, player: players[safe: index], isConnecting: isConnecting,
                                      onPlayer: onPlayer, onEditProfile: onEditProfile)
                    }
                }
            }
        }
    }

    private var duelSeats: some View {
        let players = seatedPlayers
        let you = players.first { $0.isYou }
        let rival = players.first { !$0.isYou }
        return VStack(spacing: 10) {
            PvPTicketDuelSeat(title: "Соперник", seat: 2, player: rival, isHost: rival?.isHost == true || (lobby != nil && you?.isHost == false),
                              onPlayer: onPlayer, onEditProfile: onEditProfile)
            HStack(spacing: 8) {
                Rectangle().frame(height: 0.5)
                Text("VS").font(PvPTicketStyle.mono).tracking(2)
                Rectangle().frame(height: 0.5)
            }
            .foregroundStyle(.white.opacity(0.45))
            PvPTicketDuelSeat(title: "Вы", seat: 1, player: you, isHost: false,
                              onPlayer: onPlayer, onEditProfile: onEditProfile)
        }
    }

    // MARK: Settings

    private var settingsRow: some View {
        VStack(spacing: 10) {
            Rectangle().fill(.white.opacity(0.25)).frame(height: 0.5)
            HStack(alignment: .bottom, spacing: 18) {
                fact(settings.films.map { $0.selectedLabel } ?? "∞", kind == .duel ? "ДО ПОБЕДЫ" : mediaType == .movie ? "ФИЛЬМОВ" : "СЕРИАЛОВ")
                fact(settings.frames.map { $0.selectedLabel } ?? "–", "КАДРОВ")
                fact(settings.timeLimit.map { PvPScreenText.clock(TimeInterval($0.selected)) } ?? "–", "ВРЕМЯ")
                Spacer(minLength: 0)
                settingsMenu
            }
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(PvPTicketStyle.label)
                .tracking(1)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }

    private var canEditRules: Bool {
        lobby == nil ? !isConnecting : [settings.films, settings.frames, settings.timeLimit].contains { $0?.isEditable == true }
    }

    private var settingsMenu: some View {
        Menu {
            if canEditRules {
                if let films = settings.films, kind == .room { picker(films) }
                if let frames = settings.frames { picker(frames) }
                if let time = settings.timeLimit { picker(time) }
            }
            Section {
                Toggle(isOn: Binding(get: { UserDefaults.standard.object(forKey: PvPTicketStyle.mosaicKey) as? Bool ?? true },
                                     set: { UserDefaults.standard.set($0, forKey: PvPTicketStyle.mosaicKey) })) {
                    Label("Гильош на билете", systemImage: "scribble.variable")
                }
                Button("Мой профиль", systemImage: "person.crop.circle", action: onEditProfile)
                    .disabled(model.profile == nil)
            }
            #if DEBUG
            Picker(selection: $tearFeel) {
                ForEach(PvPTearFeel.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                Text("Отрыв корешка")
                Text(PvPTearFeel(rawValue: tearFeel)?.title ?? "")
            }
            .pickerStyle(.menu)
            #endif
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .overlay { Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1) }
                .contentShape(Circle())
        }
        .foregroundStyle(.white)
        .accessibilityLabel("Правила и билет")
    }

    private func picker(_ row: PvPSettingRow) -> some View {
        Picker(selection: Binding(get: { row.selected }, set: { select(row.field, $0) })) {
            ForEach(row.options) { option in Text(option.label).tag(option.value) }
        } label: {
            Text(row.title)
            Text(row.selectedLabel)
        }
        .pickerStyle(.menu)
    }

    private func select(_ field: PvPSettingRow.Field, _ value: Int) {
        guard lobby == nil else {
            onChange(field, value)
            return
        }
        switch field {
        case .films: model.films = value
        case .frames: model.frames = value
        case .timeLimit: model.timeLimit = value
        case .health: break
        }
    }

    // MARK: Stub

    @ViewBuilder
    private var stub: some View {
        VStack(alignment: .leading, spacing: 0) {
            TicketStubHeader(title: "PvP", mediaType: mediaType)
            if let lobby {
                roomStub(lobby)
            } else {
                joinStub
            }
        }
        .modifier(TicketStubLayout(serial: nil))
        .modifier(TicketStubFrame(width: width, edgeStyle: edgeStyle))
    }

    private var joinStub: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ВОЙТИ ПО КОДУ")
                Spacer()
                if model.busy == .joining || isConnecting {
                    Text("ВХОДИМ…")
                }
            }
            .font(TicketStyle.fieldLabel)
            .tracking(TicketStyle.fieldLabelTracking)
            .padding(.top, 10)
            PvPCodeField(model: model)
                .padding(.top, 8)
            Spacer(minLength: 8)
            Button(action: onCreate) {
                HStack(spacing: 6) {
                    if model.busy == .creating || isConnecting {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "person.2")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(kind == .duel ? "ВЫЗВАТЬ НА ДУЭЛЬ" : "СОЗДАТЬ КОМНАТУ")
                        .font(TicketStyle.codeCaption)
                        .tracking(TicketStyle.codeCaptionTracking)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.busy != nil || isConnecting)
        }
    }

    private func roomStub(_ lobby: PvPLobbyScreen) -> some View {
        let seated = lobby.players.filter { $0.tone != .left }
        let ready = seated.filter { $0.tone == .ready && !$0.isHost }.count + seated.filter(\.isHost).count
        let isHostStart = lobby.primary.kind == .start
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(kind == .duel ? "КОД ДУЭЛИ" : "КОД КОМНАТЫ")
                Spacer()
                Text("\(ready) / \(seated.count) ГОТОВЫ")
            }
            .font(TicketStyle.fieldLabel)
            .tracking(TicketStyle.fieldLabelTracking)
            .padding(.top, 10)
            Button {
                UIPasteboard.general.string = lobby.invite?.text ?? lobby.code
                Haptics.shared.play(.menuSelect)
                withAnimation(.snappy) { isCopied = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.4))
                    withAnimation(.snappy) { isCopied = false }
                }
            } label: {
                PvPCodeDigits(code: lobby.code)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        if isCopied {
                            Text("СКОПИРОВАНО")
                                .font(TicketStyle.serial)
                                .tracking(TicketStyle.serialTracking)
                                .padding(.horizontal, 6)
                                .background(ink.paper)
                                .offset(y: 8)
                                .transition(.opacity)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Код \(lobby.code), скопировать")
            .overlay(alignment: .trailing) {
                if let invite = lobby.invite {
                    ShareLink(item: invite.url, message: Text(invite.text)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Поделиться приглашением")
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 6)
            PvPBarcode(code: lobby.code)
                .frame(height: 38)
                .overlay {
                    Button {
                        tear(lobby)
                    } label: {
                        Text(isTorn ? "ГОТОВ ✓" : isHostStart ? "НАЧАТЬ?" : "ГОТОВ?")
                            .font(TicketStyle.codeCaption)
                            .tracking(TicketStyle.codeCaptionTracking)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ink.paper)
                            .overlay { Rectangle().strokeBorder(lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(!lobby.primary.isEnabled)
                }
            Text(isTorn ? "НАЖМИТЕ, ЧТОБЫ ВЕРНУТЬ КОРЕШОК" : "ОТОРВИТЕ КОРЕШОК ЗА УГОЛ")
                .font(TicketStyle.serial)
                .tracking(TicketStyle.serialTracking)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.top, 5)
        }
    }

    private func tear(_ lobby: PvPLobbyScreen) {
        guard lobby.primary.isEnabled else { return }
        Haptics.shared.play(.tabBreak)
        onAction(lobby.primary.kind)
    }
}

// MARK: - Seats

private struct PvPTicketSeat: View {
    let number: Int
    let player: PvPPlayerRow?
    let isConnecting: Bool
    let onPlayer: (PvPPlayerAction, String) -> Void
    let onEditProfile: () -> Void

    private static let size: CGFloat = 46

    var body: some View {
        VStack(spacing: 4) {
            if let player {
                PvPPlayerMenu(player: player, onPlayer: onPlayer, onEditProfile: onEditProfile) {
                    PvPTicketAvatar(player: player, size: Self.size)
                }
                Text(player.isYou ? "Вы" : player.name)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: Self.size + 14)
                Text(String(format: "%02d", number))
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: Self.size, height: Self.size)
                    .overlay {
                        if isConnecting && number == 1 {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Text(String(format: "%02d", number))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                Color.clear.frame(height: 22)
            }
        }
    }
}

private struct PvPTicketDuelSeat: View {
    let title: String
    let seat: Int
    let player: PvPPlayerRow?
    let isHost: Bool
    let onPlayer: (PvPPlayerAction, String) -> Void
    let onEditProfile: () -> Void

    private static let size: CGFloat = 50

    var body: some View {
        HStack(spacing: 14) {
            if let player {
                PvPPlayerMenu(player: player, onPlayer: onPlayer, onEditProfile: onEditProfile) {
                    PvPTicketAvatar(player: player, size: Self.size)
                }
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: Self.size, height: Self.size)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(player.map { $0.isYou ? "Вы" : $0.name } ?? title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .opacity(player == nil ? 0.6 : 1)
                Text("МЕСТО \(String(format: "%02d", seat))\(player?.isHost == true || (isHost && player != nil) ? " · ХОСТ" : "")")
                    .font(PvPTicketStyle.mono)
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PvPTicketAvatar: View {
    let player: PvPPlayerRow
    let size: CGFloat

    var body: some View {
        PvPAvatarView(avatar: player.avatar, size: size,
                      isDimmed: player.tone == .away || player.tone == .offline)
            .overlay(alignment: .top) {
                if player.isHost {
                    Image(systemName: "crown.fill")
                        .font(.system(size: size * 0.22))
                        .foregroundStyle(PlaylistStyle.gold)
                        .offset(y: -size * 0.3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if player.tone == .ready, !player.isHost {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.16, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: size * 0.34, height: size * 0.34)
                        .background(PvPHealth.green, in: Circle())
                        .overlay { Circle().strokeBorder(.black, lineWidth: 1.5) }
                        .offset(x: 2, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy, value: player.tone)
    }
}

/// Native menu on a player: for yourself it opens the profile, for others the host's tools.
private struct PvPPlayerMenu<Label: View>: View {
    let player: PvPPlayerRow
    let onPlayer: (PvPPlayerAction, String) -> Void
    let onEditProfile: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Menu {
            Section(player.isYou ? "Вы" : player.name) {
                if player.isYou {
                    Button("Изменить профиль", systemImage: "person.crop.circle", action: onEditProfile)
                }
                if player.canHideForMe {
                    Button(player.isNameHidden ? "Показать имя" : "Скрыть имя", systemImage: player.isNameHidden ? "eye" : "eye.slash") {
                        onPlayer(.toggleHidden, player.uid)
                    }
                }
                if player.canHideName {
                    Button("Скрыть имя для всех", systemImage: "person.crop.circle.badge.exclamationmark") {
                        onPlayer(.hideName, player.uid)
                    }
                }
                if player.canKick {
                    Button("Удалить из комнаты", systemImage: "person.fill.xmark", role: .destructive) {
                        onPlayer(.kick, player.uid)
                    }
                }
            }
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

// MARK: - Code

private struct PvPCodeField: View {
    @ObservedObject var model: PvPTicketModel
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $model.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0.02)
                .accessibilityLabel("Код комнаты")
            PvPCodeDigits(code: model.code, cursor: isFocused ? model.code.count : nil)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .overlay(alignment: .trailing) { trailingButton }
        .onChange(of: isFocused) { _, focused in model.isEnteringCode = focused }
        .onChange(of: model.code) { _, code in
            guard PvPRoomLink.isValid(code) else { return }
            isFocused = false
            Task { await model.join() }
        }
    }

    /// Paste while the field is empty, clear once something is typed.
    @ViewBuilder
    private var trailingButton: some View {
        if model.code.isEmpty {
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in
                    model.paste(text)
                    await model.join()
                }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .controlSize(.mini)
            .tint(Color(white: 0.5))
        } else {
            Button {
                model.code = ""
                Haptics.shared.play(.menuSelect)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Стереть код")
        }
    }
}

private struct PvPCodeDigits: View {
    let code: String
    var cursor: Int?

    var body: some View {
        let digits = Array(code)
        HStack(spacing: 4) {
            ForEach(0..<PvPRoomLink.length, id: \.self) { index in
                VStack(spacing: 2) {
                    ZStack {
                        if index < digits.count {
                            Text(String(digits[index])).font(PvPTicketStyle.codeDigit)
                        } else if index == cursor {
                            Rectangle().frame(width: 1.5, height: 20)
                        } else {
                            Circle().frame(width: 3, height: 3).opacity(0.35)
                        }
                    }
                    .frame(width: 20, height: 28)
                    Rectangle().frame(width: 18, height: 1.2)
                }
                if index == 2 { Spacer().frame(width: 6) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(code.isEmpty ? "Код не введён" : code)
    }
}

/// A Code 128 look-alike drawn from the room code — decorative, not scannable.
private struct PvPBarcode: View {
    let code: String

    var body: some View {
        Canvas { context, size in
            var seed = UInt64(abs(code.hashValue)) | 1
            var x: CGFloat = 0
            var dark = true
            while x < size.width {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let unit = CGFloat(1 + (seed >> 61)) * 1.1
                if dark {
                    context.fill(Path(CGRect(x: x, y: 0, width: unit, height: size.height)), with: .foreground)
                }
                x += unit
                dark.toggle()
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Background

/// Dark grey like the playlist ticket; the guilloche lines shift colour with tilt and can be switched off.
private struct PvPTicketBackground: View {
    let isMosaic: Bool

    @ObservedObject private var motion = PosterTilt.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.posterSwipeTurn) private var swipeTurn

    var body: some View {
        GeometryReader { proxy in
            let tilt = reduceMotion ? .zero : motion.phase + SIMD2(swipeTurn, 0)
            PvPTicketStyle.paper
            .colorEffect(ShaderLibrary.pvpGuilloche(.float2(proxy.size), .float2(tilt.x, tilt.y),
                                                 .float(isMosaic ? 0.5 : 0)),
                         isEnabled: isMosaic)
        }
        .posterTilt()
    }
}

// MARK: - Flip

/// Turns the ticket over around its vertical axis. Faces are flat SwiftUI views placed in 3D with a
/// projection; the paper edge is a separate strip set at right angles, so the ticket shows its thickness
/// mid-turn like the stub does in Metal.
private struct PvPTicketFlip<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let size: CGSize
    let notch: (offset: CGFloat, radius: CGFloat)
    @ViewBuilder let front: Front
    @ViewBuilder let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    private static var thickness: CGFloat { 7 }
    private static var perspectiveDepth: CGFloat { 1400 }

    var body: some View {
        let radians = angle * .pi / 180
        let showsFront = cos(radians) >= 0
        let edgeX: CGFloat = sin(radians) >= 0 ? -1 : 1
        ZStack(alignment: .topLeading) {
            if abs(sin(radians)) > 0.02 {
                edge
                    .projectionEffect(ProjectionTransform(edgeTransform(radians: radians, side: edgeX)))
                    .brightness(-0.25 * (1 - abs(sin(radians))))
            }
            Group {
                if showsFront {
                    front.projectionEffect(ProjectionTransform(faceTransform(radians: radians)))
                } else {
                    back.projectionEffect(ProjectionTransform(faceTransform(radians: radians + .pi)))
                }
            }
            .brightness(-0.18 * (1 - abs(cos(radians))))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var edge: some View {
        let t = Self.thickness
        return VStack(spacing: 0) {
            Rectangle().frame(height: max(0, notch.offset - notch.radius))
            Color.clear.frame(height: notch.radius * 2)
            Rectangle()
        }
        .foregroundStyle(LinearGradient(colors: [PvPTicketStyle.edge, Color(white: 0.32), PvPTicketStyle.edge],
                                        startPoint: .leading, endPoint: .trailing))
        .frame(width: t, height: size.height)
    }

    private var perspective: CATransform3D {
        var p = CATransform3DIdentity
        p.m34 = -1 / Self.perspectiveDepth
        return p
    }

    private func faceTransform(radians: Double) -> CATransform3D {
        let w = size.width, h = size.height
        var t = CATransform3DMakeTranslation(-w / 2, -h / 2, 0)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(radians, 0, 1, 0))
        t = CATransform3DConcat(t, perspective)
        return CATransform3DConcat(t, CATransform3DMakeTranslation(w / 2, h / 2, 0))
    }

    /// The edge strip starts as a T×H rectangle at the origin: centre it, stand it at right angles
    /// on the chosen side of the card, then turn it with the card.
    private func edgeTransform(radians: Double, side: CGFloat) -> CATransform3D {
        let w = size.width, h = size.height, thick = Self.thickness
        var t = CATransform3DMakeTranslation(-thick / 2, -h / 2, 0)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(.pi / 2, 0, 1, 0))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(side * w / 2, 0, 0))
        t = CATransform3DConcat(t, CATransform3DMakeRotation(radians, 0, 1, 0))
        t = CATransform3DConcat(t, perspective)
        return CATransform3DConcat(t, CATransform3DMakeTranslation(w / 2, h / 2, 0))
    }
}

#if DEBUG
/// The ticket in any state: pass a lobby fixture to see it inside a room.
private struct PvPTicketPreview: View {
    var kind: PvPRoomKind = .room
    var lobby: PvPMatchState?
    var code = ""
    var mediaType: MediaType = .movie
    var edgeStyle: TicketEdgeStyle = .straight

    @StateObject private var model = PvPTicketModel(service: PvPPreviewService(), makeSession: PvPPreview.session)

    var body: some View {
        PvPTicketCard(model: model, lobby: lobby.flatMap(PvPPreview.lobby), room: nil, mediaType: mediaType,
                      width: 293, posterHeight: 440, edgeStyle: edgeStyle)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .onAppear {
                model.kind = kind
                model.code = code
            }
    }
}

private func readyGuest() -> PvPMatchState {
    var state = PvPMatchFixtures.lobbyGuest
    if let index = state.players.firstIndex(where: \.isYou) { state.players[index].ready = true }
    return state
}

#Preview("Пустой: комната") { PvPTicketPreview() }
#Preview("Пустой: дуэль") { PvPTicketPreview(kind: .duel) }
#Preview("Пустой: сериалы, фестоны") { PvPTicketPreview(mediaType: .tv, edgeStyle: .scalloped) }
#Preview("Ввод кода") { PvPTicketPreview(code: "4829") }
#Preview("Комната: хост") { PvPTicketPreview(lobby: PvPMatchFixtures.lobbyHost) }
#Preview("Комната: хост один") { PvPTicketPreview(lobby: PvPMatchFixtures.lobbyAlone) }
#Preview("Комната: гость") { PvPTicketPreview(lobby: PvPMatchFixtures.lobbyGuest) }
#Preview("Комната: гость готов (корешок оторван)") { PvPTicketPreview(lobby: readyGuest()) }
#Preview("Дуэль: лобби") { PvPTicketPreview(lobby: PvPMatchFixtures.lobbyDuel) }

#Preview("Переворот, толщина края") {
    PvPTicketFlip(angle: 62, size: CGSize(width: 293, height: 440 + TicketStubMetrics.height(width: 293, edgeStyle: .straight)),
                  notch: (440, TicketStyle.notchRadius(forWidth: 293))) {
        PvPTicketPreview()
    } back: {
        PvPTicketPreview(kind: .duel)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}

#Preview("Живой билет со сценарием") {
    @Previewable @StateObject var model = PvPTicketModel(service: PvPPreviewService(), makeSession: PvPPreview.session)
    PvPTicketView(model: model, mediaType: .movie, width: 293, posterHeight: 440, edgeStyle: .straight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
}
#endif
