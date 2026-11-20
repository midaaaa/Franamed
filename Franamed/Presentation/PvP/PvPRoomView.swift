//
//  PvPRoomView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

struct PvPRoomView: View {
    @ObservedObject var viewModel: PvPMatchViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingLeave = false
    @State private var extraBots = 0
    let mediaFacade: MediaFacadeProtocol
    let onClose: () -> Void

    private static let tick: TimeInterval = 0.5

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: Self.tick)) { context in
                let screen = viewModel.screen(at: context.date)
                stage(screen.content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) { PvPBannerStack(banners: screen.chrome.banners) }
                    .overlay {
                        if let pause = screen.chrome.pause {
                            PvPPauseView(pause: pause) { viewModel.resume() }
                        }
                    }
                    .navigationTitle(screen.chrome.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar(screen.chrome) }
                    .confirmationDialog(screen.chrome.leave.confirmation ?? "", isPresented: $isConfirmingLeave,
                                        titleVisibility: .visible) {
                        Button(screen.chrome.leave.confirmTitle, role: .destructive) { leave(screen.chrome.leave.kind) }
                    }
            }
        }
        .providesWindowGeometry()
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: viewModel.setAway(true)
            case .active: viewModel.setAway(false)
            default: break
            }
        }
    }

    /// Match, reveal and the final result share one hall, so the room never cuts away.
    @ViewBuilder
    private func stage(_ content: PvPScreen.Content) -> some View {
        let mediaType = viewModel.state.settings?.mediaType ?? .movie
        if let hall = Self.hall(content) {
            PvPHallView(match: hall.match, reveal: hall.reveal, final: hall.final, isDuel: viewModel.state.kind == .duel,
                        mediaType: mediaType, mediaFacade: mediaFacade,
                        onGuess: { viewModel.guess($0, text: $1, mediaType: mediaType) }, onSkip: { viewModel.skip() },
                        onAction: { viewModel.perform($0) }, extraBots: extraBots)
        } else {
            switch content {
            case let .closed(closed):
                PvPClosedView(screen: closed, onAction: { viewModel.perform($0) }, onClose: onClose)
            case .connecting, .lobby, .match, .reveal, .final:
                PvPConnectingView(screen: PvPConnectingScreen(title: "Подключаемся", detail: "Код \(viewModel.state.code)"))
            }
        }
    }

    private static func hall(_ content: PvPScreen.Content)
        -> (match: PvPMatchScreen?, reveal: PvPRevealScreen?, final: PvPFinalScreen?)? {
        switch content {
        case let .match(match): (match, nil, nil)
        case let .reveal(reveal): (nil, reveal, nil)
        case let .final(final): (nil, nil, final)
        default: nil
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ chrome: PvPChrome) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if chrome.leave.confirmation == nil {
                    leave(chrome.leave.kind)
                } else {
                    isConfirmingLeave = true
                }
            } label: {
                if chrome.leave.kind == .close {
                    Image(systemName: "xmark")
                } else {
                    Text(chrome.leave.title)
                }
            }
            .keyboardShortcut(.cancelAction)
        }
        #if DEBUG
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Отладка", systemImage: "ladybug") {
                Picker(selection: $extraBots) {
                    ForEach(0...7, id: \.self) { Text($0 == 0 ? "Без ботов" : "\($0)").tag($0) }
                } label: {
                    Text("Боты в зале")
                    Text("Фальшивые игроки на местах")
                }
                .pickerStyle(.menu)
            }
        }
        #endif
        ToolbarItem(placement: .topBarTrailing) {
            if chrome.canResume {
                Button("Продолжить", systemImage: "play.fill") { viewModel.resume() }
            } else if chrome.canPause {
                Button("Пауза", systemImage: "pause.fill") { viewModel.pause() }
            }
        }
    }

    private func leave(_ kind: PvPLeave.Kind) {
        Task {
            await viewModel.leave(kind)
            onClose()
        }
    }
}

// MARK: - Connecting

struct PvPConnectingView: View {
    let screen: PvPConnectingScreen

    var body: some View {
        VStack(spacing: 14) {
            WaitingSpinner()
            Text(screen.title)
                .font(.headline)
            Text(screen.detail)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Closed

struct PvPClosedView: View {
    let screen: PvPClosedScreen
    let onAction: (PvPAction.Kind) -> Void
    let onClose: () -> Void

    private var symbol: String {
        switch screen.kind {
        case .disconnected, .failed: "wifi.exclamationmark"
        case .left: "door.left.hand.open"
        case .replaced: "iphone.and.arrow.forward"
        case .kicked: "person.fill.xmark"
        case .roomGone: "questionmark.square.dashed"
        case .refused: "hand.raised.fill"
        }
    }

    var body: some View {
        ContentUnavailableView {
            Label(screen.title, systemImage: symbol)
        } description: {
            Text(screen.message)
        } actions: {
            VStack(spacing: 12) {
                if let action = screen.action {
                    PvPPrimaryButton(title: action.title, isEnabled: action.isEnabled) { onAction(action.kind) }
                }
                Button("В меню", action: onClose)
                    .font(.headline)
            }
            .frame(maxWidth: 280)
        }
    }
}

// MARK: - Banners

struct PvPBannerStack: View {
    let banners: [PvPBanner]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ForEach(banners) { banner in
                PvPBannerView(banner: banner)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, PvPStyle.inset)
        .padding(.top, 4)
        .animation(reduceMotion ? nil : .snappy, value: banners.map(\.id))
    }
}

struct PvPBannerView: View {
    let banner: PvPBanner

    private var symbol: String {
        switch banner.kind {
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .polling: "antenna.radiowaves.left.and.right"
        case .rivalOffline: "wifi.slash"
        case .rivalAway: "moon.fill"
        case .notice: "exclamationmark.circle"
        }
    }

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(banner.isUrgent ? PvPStyle.miss : .white)
            VStack(alignment: .leading, spacing: 1) {
                Text(banner.title)
                    .font(.subheadline.weight(.semibold))
                if let detail = banner.detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: PvPStyle.maxWidth)
        .glassEffect(.regular.tint(banner.isUrgent ? PvPStyle.miss.opacity(0.25) : nil), in: shape)
    }
}

// MARK: - Pause

struct PvPPauseView: View {
    let pause: PvPPauseOverlay
    let onResume: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 54))
                Text(pause.title)
                    .font(PvPStyle.largeTitle)
                Text(pause.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(pause.autoResume)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if pause.canResume {
                    PvPPrimaryButton(title: "Продолжить", action: onResume)
                        .frame(maxWidth: 260)
                        .padding(.top, 8)
                }
            }
            .multilineTextAlignment(.center)
            .padding(PvPStyle.inset)
        }
        .transition(.opacity)
    }
}

#if DEBUG
#Preview("Подключение") {
    PvPConnectingView(screen: PvPConnectingScreen(title: "Подключаемся", detail: "Код \(PvPMatchFixtures.roomCode)"))
        .preferredColorScheme(.dark)
}

#Preview("Кик") {
    if let closed = PvPPreview.closed(PvPMatchFixtures.kicked) {
        PvPClosedView(screen: closed, onAction: { _ in }, onClose: {})
            .preferredColorScheme(.dark)
    }
}

#Preview("Комнаты нет") {
    if let closed = PvPPreview.closed(PvPMatchFixtures.roomGone) {
        PvPClosedView(screen: closed, onAction: { _ in }, onClose: {})
            .preferredColorScheme(.dark)
    }
}

#Preview("Связь потеряна") {
    PvPClosedView(screen: PvPClosedScreen(kind: .disconnected, title: "Связь потеряна", message: "Место в комнате сохранено — можно вернуться",
                                          action: PvPAction(kind: .reconnect, title: "Подключиться снова", isEnabled: true)),
                  onAction: { _ in }, onClose: {})
        .preferredColorScheme(.dark)
}

#Preview("Баннер: соперник offline") {
    PvPBannerStack(banners: PvPPreview.screen(PvPMatchFixtures.rivalOffline).chrome.banners)
        .preferredColorScheme(.dark)
}

#Preview("Баннер: свернул") {
    PvPBannerStack(banners: PvPPreview.screen(PvPMatchFixtures.rivalAway).chrome.banners)
        .preferredColorScheme(.dark)
}

#Preview("Баннер: опрос") {
    PvPBannerStack(banners: PvPPreview.screen(PvPMatchFixtures.polling).chrome.banners)
        .preferredColorScheme(.dark)
}

#Preview("Баннер: переподключение") {
    PvPBannerStack(banners: PvPPreview.screen(PvPMatchFixtures.reconnecting).chrome.banners)
        .preferredColorScheme(.dark)
}

#Preview("Пауза, хост") {
    if let pause = PvPPreview.screen(PvPMatchFixtures.paused).chrome.pause {
        PvPPauseView(pause: pause) {}
            .preferredColorScheme(.dark)
    }
}

#Preview("Комната целиком") {
    PvPRoomView(viewModel: PvPMatchViewModel(session: PvPPreviewSession.room(), code: PvPMatchFixtures.roomCode),
                mediaFacade: PreviewMediaFacade()) {}
        .preferredColorScheme(.dark)
}
#endif
