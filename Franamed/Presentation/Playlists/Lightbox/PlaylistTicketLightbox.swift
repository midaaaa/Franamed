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
    @State private var hasLanded = false
    @State private var areControlsReady = false
    @State private var isClosing = false
    @State private var drag: CGFloat = 0
    @State private var webSearch: WebSearchLink?
    @State private var snapshotters = PlaylistSnapshotters()
    @State private var isShareLifted = false
    @State private var stageSize = CGSize.zero

    private static let dim = 0.2
    private static let peek: CGFloat = 18
    private static let minSpacing: CGFloat = 8
    private static let sideShrink: CGFloat = 0.14
    private static let neighborSlide: CGFloat = 70
    private static let sideInset: CGFloat = 72
    private static let heightShare: CGFloat = 0.6
    private static let prefetchRadius = 2
    private static let openDelay = Duration.milliseconds(50)
    private static let controlsDelay = Duration.milliseconds(280)
    private static let gridSettleDelay = Duration.milliseconds(34)
    private static let openAnimation = Animation.spring(response: 0.46, dampingFraction: 1)
    private static let closeAnimation = Animation.spring(response: 0.36, dampingFraction: 0.94)
    private static let dragReturnAnimation = Animation.spring(duration: 0.3)
    private static let closeDistance: CGFloat = 110
    private static let closeVelocity: CGFloat = 800
    private static let dragFadeDistance: CGFloat = 500
    private static let dragShrinkDistance: CGFloat = 1500
    private static let maxDragShrink: CGFloat = 0.1
    private static let controlsHideDistance: CGFloat = 60

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

    private var dragScale: CGFloat { 1 - min(abs(drag) / Self.dragShrinkDistance, Self.maxDragShrink) }

    private var showsControls: Bool {
        areControlsReady && !isClosing && !isShareLifted && abs(drag) < Self.controlsHideDistance
    }

    private var focusedEntry: PlaylistEntry? { playlist.playableItems.first { $0.key == focusKey } }

    var body: some View {
        ZStack {
            stage
            controls
        }
        .sheet(item: $webSearch) { link in
            SafariSheet(url: link.url).ignoresSafeArea()
        }
    }

    private var stage: some View {
        GeometryReader { proxy in
            let entries = playlist.playableItems
            let focusIndex = entries.firstIndex { $0.key == focusKey } ?? 0
            let width = ticketWidth(in: proxy.size)
            let inset = (proxy.size.width - width) / 2
            let spacing = max(inset - Self.peek - width * Self.sideShrink / 2, Self.minSpacing)
            let target = proxy.frame(in: .global)
            ZStack {
                PlaylistLightboxBackdrop(progress: flight * dragFade, dim: Self.dim)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: spacing) {
                            ForEach(Array(entries.enumerated()), id: \.element.key) { index, entry in
                                page(entry, number: index + 1, width: width, target: target,
                                     side: index == focusIndex ? 0 : (index < focusIndex ? -1 : 1))
                                    .frame(width: width, height: proxy.size.height)
                                    .scrollTransition(.interactive, axis: .horizontal) { [shrink = Self.sideShrink] content, phase in
                                        content.scaleEffect(1 - shrink * min(abs(phase.value), 1))
                                    }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                    .safeAreaPadding(.horizontal, inset)
                    .scrollPosition(id: $currentKey)
                    .scrollDisabled(!hasLanded || isClosing)
                    .onTapGesture(perform: close)
                    .onScrollPhaseChange { _, phase in
                        if phase == .idle, hasLanded, !isClosing { settle() }
                    }
                    .onAppear {
                        reader.scrollTo(focusKey, anchor: .center)
                        Task {
                            try? await Task.sleep(for: Self.openDelay)
                            open()
                        }
                    }
                }
            }
            .gesture(PlaylistLightboxPan(onChange: dragChanged, onEnd: dragEnded))
            .onChange(of: proxy.size, initial: true) { _, size in stageSize = size }
        }
        .ignoresSafeArea()
        .onChange(of: currentKey) { _, key in
            guard let key, key != focusKey else { return }
            focusKey = key
            prefetch()
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
                if isFocused, flight < 1 {
                    PlaylistEntryTicket(entry: entry, display: display, number: number, rasterizes: false)
                        .opacity(min(1, (1 - flight) * (isClosing ? 3 : 2)))
                        .allowsHitTesting(false)
                }
            }
            .onTapGesture {}
            .modifier(PlaylistLightboxPageMotion(flight: flight, isFocused: isFocused, source: source, target: target,
                                                 width: width, drag: drag, dragScale: dragScale,
                                                 neighborShift: side * Self.neighborSlide))
    }

    private func ticketWidth(in size: CGSize) -> CGFloat {
        let ratio = PlaylistTicketGeometry.height(width: TicketStyle.referenceWidth, edgeStyle: edgeStyle)
            / TicketStyle.referenceWidth
        let byHeight = size.height * Self.heightShare / ratio
        return max(0, min(TicketStyle.cardWidth(in: size, edgeStyle: edgeStyle), size.width - Self.sideInset * 2,
                          byHeight))
    }

    // MARK: Controls

    private var controls: some View {
        let entry = focusedEntry
        let display = entry.map(playlist.display(of:))
        let actions = entry.flatMap { entry in
            display.map { display in
                entry.stubContent(display: display, details: loader.details[entry.key])
                    .menuItems(onWebSearch: { webSearch = WebSearchLink(query: $0) }, onShare: share)
            }
        } ?? []
        return PlaylistLightboxControls(showsClose: showsControls,
                                        showsActions: showsControls && display?.isPlayed == true,
                                        actions: actions, onClose: close)
    }

    // MARK: Flow

    private func open() {
        prefetch()
        grid.hide(focusKey)
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
        guard areControlsReady, !isClosing else { return }
        isClosing = true
        grid.reveal(focusKey, isAnimated: false)
        grid.hide(focusKey)
        Task {
            try? await Task.sleep(for: Self.gridSettleDelay)
            withAnimation(Self.closeAnimation) {
                flight = 0
                drag = 0
            } completion: {
                onClosed()
            }
        }
    }

    private func settle() {
        grid.hide(focusKey, isAnimated: true)
        grid.reveal(focusKey, isAnimated: true)
    }

    private func dragChanged(_ translation: CGFloat) {
        guard hasLanded, !isClosing else { return }
        drag = translation
    }

    private func dragEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        guard hasLanded, !isClosing else { return }
        if abs(translation) > Self.closeDistance || abs(velocity) > Self.closeVelocity {
            close()
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
        let width = ticketWidth(in: stageSize)
        let cached = loader.cachedShareFrames(entry.key)
        var material = ShareMaterial(content: entry.stubContent(display: display, details: loader.details[entry.key])
                                         .withoutCursor(),
                                     solvedAtFrame: entry.wasCorrect == true ? max(entry.attemptsUsed, 1) : nil,
                                     frames: cached ?? .dark, roundSize: stageSize)
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
