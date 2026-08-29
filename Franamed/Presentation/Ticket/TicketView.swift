//
//  TicketView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI
import SwiftData

struct TicketView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext

    @Environment(\.displayScale) private var displayScale

    private var pixelGrid: PixelGrid { PixelGrid(displayScale: displayScale) }

    @State private var setupByMode: [MediaType: RoundSetup] = [:]
    @State private var genreNamesByType: [MediaType: [Int: String]] = [:]
    @State private var filtersSheetMediaType: MediaType?
    @State private var isShowingProfile = false
    @State private var stubReturnToken = 0
    @State private var isCardLocked = false
    @State private var isStubAway = false
    @State private var isHealingStub = false

    @State private var mediaType: MediaType = .movie
    @State private var mode: TicketGameMode = .random
    @State private var cardOffset: CGSize = .zero
    @State private var containerFrame: CGRect = .zero
    @State private var cardSize: CGSize = .zero
    @State private var cardTilt: Double = 0
    @State private var cardScale: CGFloat = 1
    @State private var hidesStub = false
    @State private var isTransitioning = false
    @State private var isRasterized = false
    @GestureState private var isDraggingCard = false

    @State private var showsMesh = true
    @State private var hapticsEnabled = true
    @State private var tintsPaper = false
    @AppStorage(DebugSettings.overlayKey) private var showsDebugOverlay = true
    @AppStorage(DebugSettings.returnStyleKey) private var returnStyle = TearReturnStyle.curled
    @AppStorage(DebugSettings.returnShrinkKey) private var shrinksOnReturn = false
    @State private var tearFrameRate = TearFrameRateProbe()

    @Namespace private var posterZoom
    @Namespace private var filtersZoom

    @MainActor private static let mediaFacade = AppFactory.makeMediaFacade()

    private static let posterPaths: [MediaType: String] = [
        .movie: "bcaBRNNuxC2N4DsffAilIueQOVc.jpg",
        .tv: "7TOPrmrJ8qO5cKJa7r6WSnjim54.jpg",
    ]

    private var card: TicketCard {
        TicketCard(mediaType: mediaType, posterPath: Self.posterPaths[mediaType], mode: mode)
    }

    var body: some View {
        NavigationStack(path: $coordinator.gamePath) {
            cardLayer
                .overlay(alignment: .top) { frameRateReadout }
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
                .fullScreenCover(item: $coordinator.presentedRound) { mediaType in
                    NavigationStack {
                        RoundView(
                            mediaFacade: AppFactory.makeMediaFacade(),
                            modelContext: modelContext,
                            mediaType: mediaType,
                            filters: setup(for: mediaType).filters,
                            frameCount: setup(for: mediaType).frameCount
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    coordinator.dismissRound()
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                    }
                    .navigationTransition(.zoom(sourceID: mediaType, in: posterZoom))
                }
                .sheet(isPresented: $isShowingProfile) {
                    ProfileSheet()
                }
                .sheet(item: $filtersSheetMediaType) { mediaType in
                    RoundFiltersView(
                        mediaFacade: AppFactory.makeMediaFacade(),
                        mediaType: mediaType,
                        setup: setup(for: mediaType)
                    ) { newSetup in
                        setupByMode[mediaType] = newSetup
                    }
                    .navigationTransition(.zoom(sourceID: mediaType, in: filtersZoom))
                }
        }
    }

    // MARK: Card cardLayer

    private var cardLayer: some View {
        GeometryReader { geo in
            let width = pixelGrid.evenAligned(max(0, geo.size.width - TicketStyle.screenInset * 2))
            let posterHeight = pixelGrid.evenAligned(width * TicketStyle.posterAspectRatio)

            cardView(width: width, posterHeight: posterHeight)
                .frame(width: width)
                .position(x: pixelGrid.snapped(geo.size.width / 2), y: pixelGrid.snapped(geo.size.height / 2))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { containerFrame = $0 }
                .onChange(of: isDraggingCard) { _, isDragging in
                    if isDragging {
                        isRasterized = true
                    } else {
                        settleAfterInterruptedDrag()
                    }
                }
        }
        .task { await loadGenreNames() }
    }

    private func cardView(width: CGFloat, posterHeight: CGFloat) -> some View {
        let isInteractive = !isTransitioning && !isCardLocked && !isStubAway

        return TicketFaceView(
            card: card,
            setup: setup(for: mediaType),
            genreNames: genreNames(for: mediaType),
            width: width,
            posterHeight: posterHeight,
            isStubGrabEnabled: !isDraggingCard,
            isRasterized: isRasterized,
            hidesStub: hidesStub,
            showsMesh: showsMesh,
            tintsPaper: tintsPaper,
            resetToken: 0,
            returnToken: stubReturnToken,
            returnStyle: returnStyle,
            posterZoom: posterZoom,
            filtersZoom: filtersZoom,
            onOpenFilters: { present { filtersSheetMediaType = mediaType } },
            onStart: { present { startRound(mediaType: mediaType) } },
            onReturnChange: { setReturning($0) },
            onStubAwayChange: { setStubAway($0) },
            probe: tearFrameRate
        )
        .equatable()
        .allowsHitTesting(isInteractive)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
        .offset(cardOffset)
        .rotationEffect(.degrees(cardTilt), anchor: .bottom)
        .scaleEffect(cardScale)
        .gesture(swipeGesture(posterHeight: posterHeight), including: isInteractive ? .all : .subviews)
    }

    // MARK: Content

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
        guard shrinksOnReturn else { return }
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

        guard cardScale != 1 else { return }
        withAnimation(TicketMotion.returnRestore) { cardScale = 1 }
    }

    private func setup(for mediaType: MediaType) -> RoundSetup {
        setupByMode[mediaType] ?? RoundSetup()
    }

    private func genreNames(for mediaType: MediaType) -> [String] {
        guard let ids = setup(for: mediaType).filters.genres, !ids.isEmpty,
              let lookup = genreNamesByType[mediaType] else { return [] }
        return ids.compactMap { lookup[$0] }
    }

    private func loadGenreNames() async {
        for mediaType in MediaType.allCases where genreNamesByType[mediaType] == nil {
            let genres = (try? await Self.mediaFacade.fetchGenres(mediaType: mediaType)) ?? []
            genreNamesByType[mediaType] = Dictionary(
                genres.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    // MARK: Swipe

    private func swipeGesture(posterHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: TicketMotion.minimumDragDistance)
            .updating($isDraggingCard) { value, state, _ in
                state = value.startLocation.y < posterHeight
            }
            .onChanged { value in
                guard value.startLocation.y < posterHeight else { return }
                cardOffset = pixelGrid.snapped(value.translation)
                cardTilt = TicketSwipe.tiltDegrees(for: value.translation)
            }
            .onEnded { value in
                guard value.startLocation.y < posterHeight else { return }
                commit(value)
            }
    }

    private func settleAfterInterruptedDrag() {
        guard !isTransitioning, cardOffset != .zero else { return }
        withAnimation(TicketMotion.snapBack) {
            cardOffset = .zero
            cardTilt = 0
        }
    }

    private func commit(_ value: DragGesture.Value) {
        guard let thrown = TicketSwipe.makeThrow(for: value) else {
            withAnimation(TicketMotion.snapBack) {
                cardOffset = .zero
                cardTilt = 0
            }
            return
        }

        let flight = TicketSwipe.flightDistance(direction: thrown.direction,
                                                card: restingCardFrame,
                                                screen: WindowMetrics.size)

        isTransitioning = true
        isRasterized = true
        withAnimation(TicketMotion.flyOut) {
            cardOffset = CGSize(width: thrown.direction.width * flight,
                                height: thrown.direction.height * flight)
            cardTilt *= TicketMotion.flightTiltGain
        } completion: {
            settle(changesMode: thrown.changesMode, step: thrown.step)
        }
    }

    private var restingCardFrame: CGRect {
        CGRect(x: containerFrame.midX - cardSize.width / 2,
               y: containerFrame.midY - cardSize.height / 2,
               width: cardSize.width, height: cardSize.height)
    }

    private func settle(changesMode: Bool, step: Int) {
        var swap = Transaction()
        swap.disablesAnimations = true
        withTransaction(swap) {
            cardOffset = CGSize(width: -cardOffset.width, height: -cardOffset.height)
            cardTilt = -cardTilt

            if changesMode {
                mode = mode.advanced(by: step)
            } else {
                mediaType = mediaType.advanced(by: step)
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

    // MARK: Debug

    @ViewBuilder
    private var frameRateReadout: some View {
        #if DEBUG
        if showsDebugOverlay {
            TicketDebugOverlay(probe: tearFrameRate,
                               showsMesh: $showsMesh,
                               hapticsEnabled: $hapticsEnabled,
                               tintsPaper: $tintsPaper)
        }
        #endif
    }
}

#Preview {
    TicketView(coordinator: AppCoordinator())
        .modelContainer(for: [RoundRecord.self, WatchedMovieCache.self], inMemory: true)
}
