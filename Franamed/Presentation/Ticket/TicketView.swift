//
//  TicketView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI
import SwiftData

struct TicketView: View {
    @StateObject private var viewModel: TicketViewModel
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext

    @Environment(\.displayScale) private var displayScale

    private var pixelGrid: PixelGrid { PixelGrid(displayScale: displayScale) }

    @State private var filtersSheetMediaType: MediaType?
    @State private var isShowingProfile = false
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
    @GestureState private var isDraggingCard = false

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
                .fullScreenCover(item: $coordinator.presentedRound) { mediaType in
                    NavigationStack {
                        RoundView(
                            mediaFacade: viewModel.mediaFacade,
                            modelContext: modelContext,
                            mediaType: mediaType,
                            filters: viewModel.setup(for: mediaType).filters,
                            frameCount: viewModel.setup(for: mediaType).frameCount
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
                        mediaFacade: viewModel.mediaFacade,
                        mediaType: mediaType,
                        setup: viewModel.setup(for: mediaType)
                    ) { newSetup in
                        viewModel.saveSetup(newSetup, for: mediaType)
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
            let container = geo.frame(in: .global)
            let centerY = Self.cardCenterY(in: container, cardHeight: cardSize.height) - container.minY

            cardView(width: width, posterHeight: posterHeight)
                .frame(width: width)
                .position(x: pixelGrid.snapped(geo.size.width / 2), y: pixelGrid.snapped(centerY))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { containerFrame = $0 }
                .onChange(of: isDraggingCard) { _, isDragging in
                    if isDragging {
                        isRasterized = true
                    } else {
                        settleAfterInterruptedDrag()
                    }
                }
        }
        .task { await viewModel.loadGenreNames() }
    }

    private func cardView(width: CGFloat, posterHeight: CGFloat) -> some View {
        let isInteractive = !isTransitioning && !isCardLocked && !isStubAway

        return TicketFaceView(
            card: viewModel.card,
            setup: viewModel.setup(for: viewModel.mediaType),
            genreNames: viewModel.genreNames(for: viewModel.mediaType),
            width: width,
            posterHeight: posterHeight,
            isStubGrabEnabled: !isDraggingCard,
            isRasterized: isRasterized,
            hidesStub: hidesStub,
            edgeStyle: TicketEdgeStyle(hasScallops: hasScallops),
            returnToken: stubReturnToken,
            posterZoom: posterZoom,
            filtersZoom: filtersZoom,
            onOpenFilters: { present { filtersSheetMediaType = viewModel.mediaType } },
            onStart: { present { startRound(mediaType: viewModel.mediaType) } },
            onReturnChange: { setReturning($0) },
            onStubAwayChange: { setStubAway($0) }
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
            cardTilt = TicketSwipe.flightTilt(from: cardTilt, direction: thrown.direction)
        } completion: {
            settle(changesMode: thrown.changesMode, step: thrown.step)
        }
    }

    private static let navigationBarHeight: CGFloat = 44

    private static func cardCenterY(in container: CGRect, cardHeight: CGFloat) -> CGFloat {
        let insets = WindowMetrics.safeAreaInsets
        let top = insets.top + navigationBarHeight
        let bottom = WindowMetrics.size.height - insets.bottom
        let half = cardHeight / 2
        guard bottom - top > cardHeight else { return container.midY }
        return min(max((insets.top + bottom) / 2, top + half), bottom - half)
    }

    private var restingCardFrame: CGRect {
        CGRect(x: containerFrame.midX - cardSize.width / 2,
               y: Self.cardCenterY(in: containerFrame, cardHeight: cardSize.height) - cardSize.height / 2,
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
        .modelContainer(for: [RoundRecord.self, WatchedRecord.self], inMemory: true)
}
