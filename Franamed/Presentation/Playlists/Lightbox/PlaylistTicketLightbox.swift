//
//  PlaylistTicketLightbox.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 22.10.2026.
//

import SwiftUI

struct PlaylistTicketLightbox: View {
    let playlist: PlaylistDetail
    let ticket: PlaylistTicket?
    @ObservedObject var loader: PlaylistTicketLoader
    let grid: PlaylistLightboxGrid
    let onClosed: () -> Void

    @AppStorage(TicketEdgeStyle.storageKey) private var hasScallops = false
    @State private var currentKey: String?
    @State private var focusKey: String
    @State private var flight: CGFloat = 0
    @State private var hasStarted = false
    @State private var hasLanded = false
    @State private var areControlsReady = false
    @State private var isClosing = false
    @State private var drag: CGFloat = 0
    @State private var webSearch: WebSearchLink?
    @State private var snapshotters = PlaylistSnapshotters()
    @State private var isShareLifted = false
    @State private var stageFrame = CGRect.zero
    @State private var closingFrame: CGRect?
    @State private var scrollFreezer = PlaylistScrollFreezer()

    private static let dim = 0.2
    private static let peek: CGFloat = 18
    private static let minSpacing: CGFloat = 8
    private static let sideShrink: CGFloat = 0.14
    private static let neighborSlide: CGFloat = 70
    private static let sideInset: CGFloat = 72
    private static let heightShare: CGFloat = 0.8
    private static let galleryThreshold: CGFloat = 0.25
    private static let galleryGap: CGFloat = 24
    private static let prefetchRadius = 2
    private static let openDelay = Duration.milliseconds(50)
    private static let controlsDelay = Duration.milliseconds(280)
    private static let gridSettleDelay = Duration.milliseconds(34)
    private static let openAnimation = Animation.spring(response: 0.46, dampingFraction: 1)
    private static let closeDuration = 0.36
    private static let closeBounce = 0.06
    private static let closeAnimation = Animation.spring(duration: closeDuration, bounce: closeBounce)
    private static let dragReturnAnimation = Animation.spring(duration: 0.3)
    private static let recenterAnimation = Animation.smooth(duration: 0.5)
    private static let closeDistance: CGFloat = 110
    private static let closeVelocity: CGFloat = 800
    private static let dragFadeDistance: CGFloat = 500
    private static let dragShrinkDistance: CGFloat = 1500
    private static let maxDragShrink: CGFloat = 0.1
    private static let controlsHideDistance: CGFloat = 60
    private static let maxReleaseSpeed: CGFloat = 2500

    init(playlist: PlaylistDetail, startKey: String, ticket: PlaylistTicket?, loader: PlaylistTicketLoader,
         grid: PlaylistLightboxGrid, onClosed: @escaping () -> Void) {
        self.playlist = playlist
        self.ticket = ticket
        self.loader = loader
        self.grid = grid
        self.onClosed = onClosed
        _currentKey = State(initialValue: startKey)
        _focusKey = State(initialValue: startKey)
    }

    private var edgeStyle: TicketEdgeStyle { TicketEdgeStyle(hasScallops: hasScallops) }

    private var dragFade: CGFloat { 1 - min(abs(drag) / Self.dragFadeDistance, 1) * 0.6 }

    private var focusedEntry: PlaylistEntry? { playlist.playableItems.first { $0.key == focusKey } }

    private var isPresenting: Bool { isShareLifted || webSearch != nil }

    private var showsButtons: Bool {
        areControlsReady && !isClosing && !isShareLifted && abs(drag) < Self.controlsHideDistance
    }

    var body: some View {
        VerticalToolbarSwitch { hasVerticalToolbar in
            lightbox(hasVerticalToolbar: hasVerticalToolbar)
        }
        .sheet(item: $webSearch) { link in
            SafariSheet(url: link.url).ignoresSafeArea()
        }
    }

    private func lightbox(hasVerticalToolbar: Bool) -> some View {
        NavigationStack {
            stage
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !hasVerticalToolbar { PlaylistLightboxCloseButton(isShown: showsButtons, onClose: close) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !hasVerticalToolbar {
                        PlaylistLightboxButtons(actions: actions, isShown: showsButtons && isFocusedPlayed,
                                                width: ticketWidth(in: (closingFrame ?? stageFrame).size))
                    }
                }
                .toolbar {
                    if hasVerticalToolbar {
                        PlaylistLightboxToolbar(actions: actions,
                                                areActionsEnabled: areControlsReady && isFocusedPlayed,
                                                onClose: close)
                    }
                }
                .toolbarVisibility(hasVerticalToolbar && !isClosing ? .visible : .hidden,
                                   for: .navigationBar, .bottomBar)
                .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
                .navigationBarTitleDisplayMode(.inline)
                .containerBackground(.clear, for: .navigation)
        }
    }

    private var stage: some View {
        ZStack {
            PlaylistLightboxBackdrop(progress: flight * dragFade, dim: Self.dim)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            pages
        }
        .gesture(PlaylistLightboxPan(isEnabled: !isPresenting, onChange: dragChanged, onEnd: dragEnded))
        .onChange(of: currentKey) { _, key in
            guard let key, key != focusKey, !isClosing else { return }
            focusKey = key
            prefetch()
        }
    }

    private var pages: some View {
        GeometryReader { proxy in
            let entries = playlist.playableItems
            let focusIndex = entries.firstIndex { $0.key == focusKey } ?? 0
            let live = proxy.frame(in: .global)
            let target = closingFrame ?? live
            let width = ticketWidth(in: target.size)
            let spacing = pageSpacing(in: target.width, ticketWidth: width)
            let inset = (target.width - width) / 2
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: spacing) {
                        ForEach(Array(entries.enumerated()), id: \.element.key) { index, entry in
                            page(entry, number: index + 1, width: width, target: target,
                                 side: index == focusIndex ? 0 : (index < focusIndex ? -1 : 1))
                                .frame(width: width, height: target.height)
                                .scrollTransition(.interactive, axis: .horizontal) { [shrink = Self.sideShrink] content, phase in
                                    content.scaleEffect(1 - shrink * min(abs(phase.value), 1))
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .background { PlaylistScrollFreezerAnchor(freezer: scrollFreezer) }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollTargetBehavior(PlaylistLightboxScrollBehavior(freezer: scrollFreezer))
                .safeAreaPadding(.horizontal, inset)
                .scrollPosition(id: $currentKey)
                .scrollDisabled(!hasLanded || isClosing)
                .onTapGesture(perform: close)
                .onScrollPhaseChange { _, phase in
                    if !scrollFreezer.isAligned, !isClosing, phase != .interacting { recenter(reader) }
                    if phase == .idle, hasLanded, !isClosing { settle() }
                }
                .onAppear {
                    Task {
                        try? await Task.sleep(for: Self.openDelay)
                        open()
                    }
                }
                .onChange(of: isClosing) { _, isClosing in
                    if isClosing { withAnimation(Self.closeAnimation) { reader.scrollTo(focusKey, anchor: .center) } }
                }
                .onChange(of: isPresenting) { _, isPresenting in
                    if isPresenting, !scrollFreezer.cancelTouch() { recenter(reader) }
                }
                .onChange(of: target.size, initial: true) { _, size in
                    if size.width > 0 { reader.scrollTo(focusKey, anchor: .center) }
                }
                .frame(width: target.width, height: target.height)
                .opacity(hasStarted ? 1 : 0)
                .offset(x: target.minX - live.minX, y: target.minY - live.minY)
            }
            .onChange(of: live, initial: true) { _, frame in stageFrame = frame }
        }
    }

    // MARK: Page

    private func page(_ entry: PlaylistEntry, number: Int, width: CGFloat, target: CGRect, side: CGFloat) -> some View {
        let display = playlist.display(of: entry)
        let isFocused = entry.key == focusKey
        let source = isFocused ? grid.frames[entry.key] : nil
        return PlaylistBigTicket(entry: entry, display: display, number: number, playlist: ticket,
                                 details: loader.details[entry.key], width: width,
                                 isLive: hasLanded || isFocused, snapshotter: snapshotters[entry.key],
                                 isStubLifted: isFocused && isShareLifted)
            .overlay {
                if isFocused, flight < 1 || drag != 0 {
                    PlaylistEntryTicket(entry: entry, display: display, number: number, rasterizes: false)
                        .opacity(min(1, (1 - flight) * (isClosing ? 3 : 2)))
                        .allowsHitTesting(false)
                }
            }
            .onTapGesture {}
            .modifier(PlaylistLightboxPageMotion(flight: flight, isFocused: isFocused, source: source, target: target,
                                                 width: width, drag: drag, shrinkDistance: Self.dragShrinkDistance,
                                                 maxShrink: Self.maxDragShrink,
                                                 neighborShift: side * Self.neighborSlide))
    }

    private func ticketWidth(in size: CGSize) -> CGFloat {
        let ratio = PlaylistTicketGeometry.height(width: TicketStyle.referenceWidth, edgeStyle: edgeStyle)
            / TicketStyle.referenceWidth
        let byHeight = size.height * Self.heightShare / ratio
        return max(0, min(TicketStyle.cardWidth(in: size, edgeStyle: edgeStyle), size.width - Self.sideInset * 2,
                          byHeight))
    }

    private func pageSpacing(in stageWidth: CGFloat, ticketWidth width: CGFloat) -> CGFloat {
        let peekSpacing = (stageWidth - width) / 2 - Self.peek - width * Self.sideShrink / 2
        guard peekSpacing <= width * Self.galleryThreshold else {
            return Self.galleryGap * TicketStyle.zoom(forWidth: width)
        }
        return max(peekSpacing, Self.minSpacing)
    }

    // MARK: Controls

    private var isFocusedPlayed: Bool { focusedEntry.map { playlist.display(of: $0).isPlayed } ?? false }

    private var actions: [FlipMenuItem] {
        guard let entry = focusedEntry else { return [] }
        let display = playlist.display(of: entry)
        return entry.stubContent(display: display, details: loader.details[entry.key])
            .menuItems(onWebSearch: { webSearch = WebSearchLink(query: $0) }, onShare: share)
    }

    // MARK: Flow

    private func open() {
        prefetch()
        grid.hide(focusKey)
        hasStarted = true
        withAnimation(Self.openAnimation, completionCriteria: .removed) {
            flight = 1
        } completion: {
            hasLanded = true
        }
        Task {
            try? await Task.sleep(for: Self.controlsDelay)
            areControlsReady = true
        }
    }

    private func close() {
        close(releaseSpeed: 0)
    }

    private func close(releaseSpeed: CGFloat) {
        guard areControlsReady, !isClosing else { return }
        scrollFreezer.stop()
        closingFrame = stageFrame
        isClosing = true
        let scrolls = grid.reveal(focusKey, isAnimated: false)
        grid.hide(focusKey)
        guard scrolls else {
            flyHome(releaseSpeed: releaseSpeed)
            return
        }
        Task {
            try? await Task.sleep(for: Self.gridSettleDelay)
            flyHome(releaseSpeed: releaseSpeed)
        }
    }

    private func flyHome(releaseSpeed: CGFloat) {
        let speed = min(max(releaseSpeed, -Self.maxReleaseSpeed), Self.maxReleaseSpeed)
        let progressSpeed = abs(drag) > 1 ? -speed / drag : 0
        withAnimation(.interpolatingSpring(duration: Self.closeDuration, bounce: Self.closeBounce,
                                           initialVelocity: progressSpeed)) {
            drag = 0
        }
        withAnimation(Self.closeAnimation) {
            flight = 0
        } completion: {
            onClosed()
        }
    }

    private func recenter(_ reader: ScrollViewProxy) {
        scrollFreezer.align()
        withAnimation(Self.recenterAnimation) { reader.scrollTo(focusKey, anchor: .center) }
    }

    private func settle() {
        grid.hide(focusKey, isAnimated: true)
        grid.reveal(focusKey, isAnimated: true)
    }

    private func dragChanged(_ translation: CGFloat) {
        guard hasLanded, !isClosing, !isPresenting else { return }
        drag = translation
    }

    private func dragEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        guard hasLanded, !isClosing else { return }
        if abs(translation) > Self.closeDistance || abs(velocity) > Self.closeVelocity {
            close(releaseSpeed: velocity)
        } else {
            withAnimation(Self.dragReturnAnimation) { drag = 0 }
        }
    }

    private func prefetch() {
        let entries = playlist.playableItems
        guard let index = entries.firstIndex(where: { $0.key == focusKey }) else { return }
        let near = entries[max(0, index - Self.prefetchRadius)...min(entries.count - 1, index + Self.prefetchRadius)]
            .filter { $0.state == .completed }
        loader.loadDetails(near.map(\.key))
        loader.prefetchPosters(near.compactMap(\.largePosterImageURL))
        if entries[index].state == .completed {
            Task { _ = await loader.shareFrames(for: entries[index], in: playlist.id) }
        }
    }

    // MARK: Share

    private func share() {
        guard let entry = focusedEntry, !isShareLifted, areControlsReady, !isClosing else { return }
        let display = playlist.display(of: entry)
        let snapshotter = snapshotters[entry.key]
        guard display.isPlayed, let presenter = snapshotter.hostController(),
              let source = snapshotter.frameInWindow() else { return }
        let width = ticketWidth(in: stageFrame.size)
        let cached = loader.cachedShareFrames(entry.key)
        var material = ShareMaterial(content: entry.stubContent(display: display, details: loader.details[entry.key])
                                         .withoutCursor(),
                                     solvedAtFrame: entry.wasCorrect == true ? max(entry.attemptsUsed, 1) : nil,
                                     frames: cached ?? .dark, roundSize: stageFrame.size)
        material.stubWidth = width
        material.isFramePending = cached == nil
        let launch = ShareLaunch(snapshotter: snapshotter, source: source,
                                 startsOnBack: !(snapshotter.engine?.isFrontVisible ?? true), stubWidth: width)
        let model = ShareSheetModel(material: material, launch: launch,
                                    posterPath: entry.posterURL.flatMap { URL(string: $0)?.lastPathComponent })
        ShareSheetController.present(model: model, from: presenter, onLift: { isShareLifted = true },
                                     onFinish: { isShareLifted = false })
        guard cached == nil else { return }
        Task { await model.apply(loader.shareFrames(for: entry, in: playlist.id)) }
    }
}
