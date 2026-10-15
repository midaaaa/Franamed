//
//  ShareSheetView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.10.2026.
//

import SwiftUI

struct ShareSheetView: View {
    @ObservedObject var model: ShareSheetModel

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = min(proxy.size.height, model.sheetHeight ?? proxy.size.height)
            ZStack(alignment: .topLeading) {
                ShareCardFrame(lift: ShareSheetLayout.cardLift(panelHeight: model.panelHeight),
                               aspect: model.format.aspect, inset: ShareSheetLayout.topInset(for: model.format),
                               stickerness: model.format == .sticker ? 1 : 0, height: cardHeight,
                               width: proxy.size.width, model: model)
                    .animation(.snappy, value: model.format)
                    .offset(y: proxy.size.height - cardHeight)

                SharePanel(material: model.material, mode: $model.mode, background: $model.background,
                           format: $model.format, onShare: model.send)
                    .frame(width: proxy.size.width, height: model.tallestPanel, alignment: .bottom)
                    .allowsHitTesting(!model.isFlying)
                    .offset(y: ShareSheetLayout.panelTop(height: proxy.size.height, panelHeight: model.tallestPanel))
            }
        }
        .ignoresSafeArea()
        .onChange(of: model.stubContent) { model.prepareStub() }
        .task { await model.loadExtras() }
    }
}

private struct ShareCardFrame: View, Animatable {
    var lift: CGFloat
    var aspect: CGFloat
    var inset: CGFloat
    var stickerness: CGFloat
    let height: CGFloat
    let width: CGFloat
    @ObservedObject var model: ShareSheetModel

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(lift, aspect), AnimatablePair(inset, stickerness)) }
        set {
            lift = newValue.first.first
            aspect = newValue.first.second
            inset = newValue.second.first
            stickerness = newValue.second.second
        }
    }

    var body: some View {
        let canvas = ShareSheetLayout.canvas(width: width, top: inset, bottom: height - lift, aspect: aspect)
        let scale = canvas.width / ShareFormat.baseWidth
        ZStack(alignment: .topLeading) {
            ShareCard(material: model.material, mode: model.mode, background: model.shownBackground, format: model.format,
                      showsStub: false, height: canvas.height / scale, stickerness: stickerness, clipsBackdrop: false)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
                .clipShape(.rect(cornerRadius: ShareSheetLayout.cardCornerRadius, style: .continuous))
            ShareCard(material: model.material, mode: model.mode, background: model.shownBackground, format: model.format,
                      showsStub: model.showsStub, height: canvas.height / scale, stickerness: stickerness,
                      showsBackdrop: false)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .offset(x: canvas.minX, y: canvas.minY)
    }
}

#Preview("Поделиться") {
    let model = ShareSheetModel(material: .preview, launch: ShareLaunch(source: .zero, startsOnBack: false),
                                posterPath: nil)
    model.showsStub = true
    return ShareSheetView(model: model)
        .preferredColorScheme(.dark)
}
