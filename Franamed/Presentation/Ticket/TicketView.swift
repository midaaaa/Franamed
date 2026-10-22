//
//  TicketView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI

struct TicketView: View {
    @StateObject private var viewModel: TicketViewModel
    @StateObject private var playlists = PlaylistsViewModel()
    @ObservedObject var coordinator: AppCoordinator

    @Environment(\.displayScale) private var displayScale
    @Environment(\.windowGeometry) private var window

    private var pixelGrid: PixelGrid { PixelGrid(displayScale: displayScale) }

    @State private var filtersSheetMediaType: MediaType?
    @State private var playlistSheet: PlaylistSheetRoute?
    @State private var isShowingProfile = false
    @State private var isRoundDismissLocked = false
    @State private var stubReturnToken = 0
    @State private var isCardLocked = false
    @State private var isStubAway = false
    @State private var isHealingStub = false

    @State private var cardOffset: CGSize = .zero
    @State private var containerFrame: CGRect = .zero
    @State private var cardSize: CGSize = .zero
    @State private var cardTilt: Double = 0
    @State private var cardScale: CGFloat = 1
    @State private var hidesStub = false
    @State private var isTransitioning = false
    @State private var isRasterized = false
    @State private var isDraggingCard = false

    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false

    @Namespace private var posterZoom
    @Namespace private var filtersZoom

    init(coordinator: AppCoordinator, mediaFacade: MediaFacadeProtocol) {
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: TicketViewModel(mediaFacade: mediaFacade))
    }

    var body: some View {
        NavigationStack(path: $coordinator.gamePath) {
            cardLayer
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingProfile = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
                .onChange(of: coordinator.presentedRound) { _, round in
                    guard round == nil else { return }
                    scheduleStubReturn()
                }
                .fullScreenCover(item: $coordinator.presentedRound, onDismiss: refreshPlayedPlaylist) { mediaType in
                    RoundNavigation {
                        RoundView(
                            mediaFacade: viewModel.mediaFacade,
                            mediaType: mediaType,
                            mode: viewModel.mode,
                            filters: viewModel.setup(for: mediaType).filters,
                            frameCount: viewModel.setup(for: mediaType).frameCount,
                            shuffle: viewModel.setup(for: mediaType).shuffle,
                            playlists: playlists,
                            playlistID: viewModel.mode == .collection ? playlists.selectedID(for: mediaType) : nil,
                            isDismissLocked: $isRoundDismissLocked
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    coordinator.dismissRound()
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .keyboardShortcut(.cancelAction)
                            }
                        }
                    }
                    .ignoresSafeArea()
                    .interactiveDismissDisabled(isRoundDismissLocked)
                    .environment(\.resultStubWidth, ticketWidth)
                    .navigationTransition(.zoom(sourceID: mediaType, in: posterZoom))
                }
                .sheet(isPresented: $isShowingProfile) {
                    ProfileSheet(mediaFacade: viewModel.mediaFacade)
                }
                .sheet(item: $filtersSheetMediaType) { mediaType in
                    RoundFiltersView(
                        mediaFacade: viewModel.mediaFacade,
                        source: viewModel.mode.roundSource,
                        mediaType: mediaType,
                        setup: viewModel.setup(for: mediaType),
                        onPlayOptionsChange: { frameCount, shuffle in
                            var setup = viewModel.setup(for: mediaType)
                            setup.frameCount = frameCount
                            setup.shuffle = shuffle
                            viewModel.saveSetup(setup, for: mediaType)
                        }
                    ) { newSetup in
                        viewModel.saveSetup(newSetup, for: mediaType)
                    }
                    .navigationTransition(.zoom(sourceID: mediaType, in: filtersZoom))
                }
                .sheet(item: $playlistSheet, onDismiss: playlists.markOpenedSeen) { route in
                    PlaylistPickerSheet(playlists: playlists, mediaType: route.mediaType, openedID: route.openedID) {
                        playlistSheet = nil
                    }
                    .ignoresSafeArea()
                    .presentationSizing(.page)
                    .task { await playlists.load() }
                    .navigationTransition(.zoom(sourceID: route.mediaType, in: route.fromPoster ? posterZoom : filtersZoom))
                }
        }
    }

    private func refreshPlayedPlaylist() {
        guard viewModel.mode == .collection else { return }
        Task { await playlists.reloadProgress() }
    }

    // MARK: Card cardLayer

    private var cardLayer: some View {
        GeometryReader { geo in
            let width = pixelGrid.evenAligned(TicketStyle.cardWidth(in: geo.size, edgeStyle: edgeStyle))
            let posterHeight = pixelGrid.evenAligned(width * TicketStyle.posterAspectRatio)
            let cardHeight = posterHeight + TicketStubMetrics.height(width: width, edgeStyle: edgeStyle)
            let centerY = Self.cardCenterY(containerHeight: geo.size.height, cardHeight: cardHeight)
            let overscan = pixelGrid.aligned(max(geo.size.width - width, geo.size.height - cardHeight) / 2
                                             + Self.tearOverscanMargin, rule: .up)

            cardView(width: width, posterHeight: posterHeight, tearOverscan: overscan)
                .frame(width: width)
                .position(x: pixelGrid.snapped(geo.size.width / 2), y: pixelGrid.snapped(centerY))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { containerFrame = $0 }
        }
        .ignoresSafeArea(.keyboard)
        .task { await viewModel.loadGenreNames() }
        .task { await playlists.load() }
    }

    private func cardView(width: CGFloat, posterHeight: CGFloat, tearOverscan: CGFloat) -> some View {
        let isInteractive = !isTransitioning && !isCardLocked && !isStubAway
        let card = currentCard

        return TicketFaceView(
            card: card,
            setup: viewModel.setup(for: viewModel.mediaType),
            genreNames: viewModel.genreNames(for: viewModel.mediaType),
            width: width,
            posterHeight: posterHeight,
            isStubGrabEnabled: !isDraggingCard,
            isRasterized: isRasterized,
            hidesStub: hidesStub,
            edgeStyle: edgeStyle,
            tearOverscan: tearOverscan,
            returnToken: stubReturnToken,
            posterZoom: posterZoom,
            filtersZoom: filtersZoom,
            onOpenFilters: { present { openStubSheet() } },
            onStart: { present { startOrOpenPlaylist() } },
            onOpenPoster: openPlaylistFromPoster,
            onReturnChange: { setReturning($0) },
            onStubAwayChange: { setStubAway($0) }
        )
        .equatable()
        .allowsHitTesting(isInteractive)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
        .offset(cardOffset)
        .rotationEffect(.degrees(cardTilt), anchor: .bottom)
        .scaleEffect(cardScale)
        .gesture(TicketPanGesture(posterHeight: posterHeight, isEnabled: isInteractive,
                                  onChange: { dragChanged($0) },
                                  onEnd: { dragEnded(translation: $0, velocity: $1) }))
    }

    // MARK: Content

    private var currentCard: TicketCard {
        var card = viewModel.card
        if card.mode == .collection {
            card.playlist = playlists.ticket(for: card.mediaType)
        }
        return card
    }

    private func openStubSheet() {
        guard viewModel.mode == .collection else {
            filtersSheetMediaType = viewModel.mediaType
            return
        }
        playlistSheet = PlaylistSheetRoute(mediaType: viewModel.mediaType, fromPoster: false)
    }

    private func startOrOpenPlaylist() {
        guard !currentCard.canTear else {
            startRound(mediaType: viewModel.mediaType)
            return
        }
        playlistSheet = PlaylistSheetRoute(mediaType: viewModel.mediaType, fromPoster: false,
                                           openedID: playlists.selectedID(for: viewModel.mediaType))
    }

    private func openPlaylistFromPoster() {
        guard viewModel.mode == .collection else { return }
        let mediaType = viewModel.mediaType
        guard let selectedID = playlists.selectedID(for: mediaType) else { return }
        present {
            playlistSheet = PlaylistSheetRoute(mediaType: mediaType, fromPoster: true, openedID: selectedID)
        }
    }

    private func scheduleStubReturn() {
        Task {
            try? await Task.sleep(for: .seconds(TicketMotion.stubReturnDelay))
            stubReturnToken += 1
        }
    }

    private func startRound(mediaType: MediaType) {
        isCardLocked = true
        withAnimation(TicketMotion.roundCoverIn) { hidesStub = true }
        coordinator.showRound(mediaType: mediaType)
        withAnimation(.easeOut(duration: TicketMotion.returnShrinkDuration)) {
            cardScale = 1 - TicketMotion.returnShrink
        }
    }

    private func setStubAway(_ away: Bool) {
        isStubAway = away
        if !away { isCardLocked = false }
    }

    private func setReturning(_ active: Bool) {
        guard !active else {
            isHealingStub = true
            return
        }

        let healed = isHealingStub
        isHealingStub = false

        if healed {
            hidesStub = false
        } else {
            withAnimation(TicketMotion.roundCoverIn) { hidesStub = false }
        }
        revealPendingStamp()

        guard cardScale != 1 else { return }
        withAnimation(TicketMotion.returnRestore) { cardScale = 1 }
    }
    
    private func revealPendingStamp() {
        guard viewModel.mode == .collection,
              let id = playlists.selectedID(for: viewModel.mediaType),
              playlists.hasPendingStamp(id) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(TicketMotion.stampDelay))
            withAnimation(TicketMotion.stampDrop) { playlists.revealStamp(id) }
            try? await Task.sleep(for: .seconds(TicketMotion.stampImpactDelay))
            Haptics.shared.play(.stamp)
        }
    }

    // MARK: Swipe

    private func dragChanged(_ translation: CGSize) {
        if !isDraggingCard {
            isDraggingCard = true
            isRasterized = true
        }
        cardOffset = pixelGrid.snapped(translation)
        cardTilt = TicketSwipe.tiltDegrees(for: translation, zoom: TicketStyle.zoom(forWidth: ticketWidth))
    }

    private func dragEnded(translation: CGSize, velocity: CGSize) {
        isDraggingCard = false
        guard let thrown = TicketSwipe.makeThrow(translation: translation, velocity: velocity) else {
            withAnimation(TicketMotion.snapBack) {
                cardOffset = .zero
                cardTilt = 0
            }
            return
        }

        let flight = TicketSwipe.flightDistance(direction: thrown.direction,
                                                card: restingCardFrame,
                                                screen: window.size)

        isTransitioning = true
        isRasterized = true
        withAnimation(TicketMotion.flyOut) {
            cardOffset = CGSize(width: thrown.direction.width * flight,
                                height: thrown.direction.height * flight)
            cardTilt = TicketSwipe.flightTilt(from: cardTilt, direction: thrown.direction)
        } completion: {
            settle(changesMode: thrown.changesMode, step: thrown.step)
        }
    }

    private static let navigationBarHeight: CGFloat = 44
    private static let tearOverscanMargin: CGFloat = 48

    private static func cardCenterY(containerHeight: CGFloat, cardHeight: CGFloat) -> CGFloat {
        guard containerHeight > cardHeight else { return containerHeight / 2 }
        let half = cardHeight / 2
        return min(max(containerHeight / 2 - navigationBarHeight / 2, half), containerHeight - half)
    }

    private var edgeStyle: TicketEdgeStyle { TicketEdgeStyle(hasScallops: hasScallops) }

    private var ticketWidth: CGFloat {
        let width = TicketStyle.cardWidth(in: containerFrame.size, edgeStyle: edgeStyle)
        return width > 0 ? pixelGrid.evenAligned(width) : TicketStyle.referenceWidth
    }

    private var restingCardFrame: CGRect {
        CGRect(x: containerFrame.midX - cardSize.width / 2,
               y: containerFrame.minY + Self.cardCenterY(containerHeight: containerFrame.height, cardHeight: cardSize.height)
                   - cardSize.height / 2,
               width: cardSize.width, height: cardSize.height)
    }

    private func settle(changesMode: Bool, step: Int) {
        var swap = Transaction()
        swap.disablesAnimations = true
        withTransaction(swap) {
            cardOffset = CGSize(width: -cardOffset.width, height: -cardOffset.height)
            cardTilt = -cardTilt

            if changesMode {
                viewModel.select(mode: viewModel.mode.advanced(by: step))
            } else {
                viewModel.select(mediaType: viewModel.mediaType.advanced(by: step))
            }
        }

        Task { @MainActor in
            withAnimation(TicketMotion.settle) {
                cardOffset = .zero
                cardTilt = 0
            } completion: {
                isTransitioning = false
            }
        }
    }

    private func present(_ action: @escaping () -> Void) {
        isRasterized = false
        Task { @MainActor in action() }
    }
}

#Preview {
    TicketView(coordinator: AppCoordinator(), mediaFacade: PreviewMediaFacade())
}
