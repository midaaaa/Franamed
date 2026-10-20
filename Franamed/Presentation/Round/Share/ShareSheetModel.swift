//
//  ShareSheetModel.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.10.2026.
//

import Combine
import Metal
import SwiftUI

@MainActor
final class ShareSheetModel: ObservableObject {
    @Published var material: ShareMaterial
    @Published var mode = ShareMode.answer
    @Published var background = ShareBackground.hall
    @Published var format = ShareFormat.story {
        didSet { if format != oldValue { onFormatChange(format) } }
    }
    @Published var showsStub = false
    @Published var isFlying = false

    let launch: ShareLaunch
    private let panelHeights: [ShareFormat: CGFloat]
    @Published var sheetHeight: CGFloat?
    @Published var cardShape: ShareCardShape
    @Published private(set) var stubWidth: CGFloat
    var presentActivity: ([Any]) -> Void = { _ in }
    var onFormatChange: (ShareFormat) -> Void = { _ in }

    private let posterURL: URL?
    private var faceTextures: [ResultStubContent: MTLTexture] = [:]

    private static let posterBase = "https://image.tmdb.org/t/p/original/"
    private static let reveal = Animation.easeOut(duration: 0.3)

    init(material: ShareMaterial, launch: ShareLaunch, posterPath: String?) {
        let posterURL = posterPath.flatMap { URL(string: Self.posterBase + $0.trimmingPrefix("/")) }
        var material = material
        material.isPosterPending = material.poster == nil && posterURL != nil
        self.material = material
        self.launch = launch
        self.posterURL = posterURL
        panelHeights = Dictionary(uniqueKeysWithValues: ShareFormat.allCases.map {
            ($0, SharePanel.height(for: material, format: $0, width: material.roundSize.width))
        })
        cardShape = ShareCardShape(format: .story, panelHeight: panelHeights[.story] ?? 0)
        stubWidth = material.stubWidth
    }

    func updateStubWidth(windowSize: CGSize) {
        let edgeStyle = TicketEdgeStyle.stored
        let opened = TicketStyle.cardWidth(in: material.roundSize, edgeStyle: edgeStyle)
        guard opened > 0 else { return }
        stubWidth = material.stubWidth * TicketStyle.cardWidth(in: windowSize, edgeStyle: edgeStyle) / opened
    }

    var tallestPanel: CGFloat { panelHeights.values.max() ?? 0 }

    func panelHeight(for format: ShareFormat) -> CGFloat {
        panelHeights[format] ?? 0
    }

    func cardShape(for format: ShareFormat) -> ShareCardShape {
        ShareCardShape(format: format, panelHeight: panelHeight(for: format))
    }

    var stubContent: ResultStubContent {
        mode.stub(of: material.content)
    }

    func layout(in size: CGSize) -> ShareSheetLayout {
        let target = min(size.height, sheetHeight ?? size.height)
        return ShareSheetLayout(size: CGSize(width: size.width, height: target), shape: cardShape,
                                stubWidth: stubWidth)
            .offsetBy(dy: size.height - target)
    }

    // MARK: Stub

    func prepareStub(for mode: ShareMode? = nil) {
        let content = (mode ?? self.mode).stub(of: material.content)
        if material.stubs[content] == nil, let face = launch.renderStub(content) {
            material.stubs[content] = ShareStubImage(face: face)
        }
        _ = faceTexture(for: content)
    }

    func faceTexture() -> MTLTexture? {
        faceTexture(for: stubContent)
    }

    private func faceTexture(for content: ResultStubContent) -> MTLTexture? {
        if let texture = faceTextures[content] { return texture }
        let texture = launch.renderFace(content)
        faceTextures[content] = texture
        return texture
    }

    func shadowImage() -> UIImage? {
        material.stubs[stubContent].flatMap { ShareStubShadow.shadowOnly($0.face) }
    }

    var shownBackground: ShareBackground {
        background.shown(in: mode, material: material)
    }

    // MARK: Loading

    func loadExtras() async {
        async let hall: Void = loadHall()
        async let poster: Void = loadPoster()
        _ = await (hall, poster)
    }

    private func loadHall() async {
        async let answer = renderHall(for: .answer)
        async let riddle = renderHall(for: .riddle)
        let halls = await (answer, riddle)
        withAnimation(Self.reveal) {
            material.halls[.answer] = halls.0
            material.halls[.riddle] = halls.1
        }
    }

    private func renderHall(for mode: ShareMode) async -> UIImage? {
        await HallSnapshot.image(sample: material.light(for: mode), scene: HallScene(), size: ShareMaterial.hallSize,
                                 frameTop: ShareMaterial.cardFrame.minY, frameBottom: ShareMaterial.cardFrame.maxY, scale: 3)
    }

    private func loadPoster() async {
        guard material.poster == nil, let posterURL else { return }
        let downloaded = await FrameDownloads.shared.image(for: posterURL)
        let poster = if let downloaded { await SharePosterBackdrop.make(downloaded) } else { UIImage?.none }
        withAnimation(Self.reveal) {
            material.poster = poster
            material.isPosterPending = false
        }
    }

    // MARK: Send

    func send() {
        let card = ShareCard(material: material, mode: mode, background: shownBackground, format: format)
        guard let item = ShareExport.item(card: card) else { return }
        presentActivity([item])
    }
}
