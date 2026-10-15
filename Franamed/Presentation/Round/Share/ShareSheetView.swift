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
            ZStack(alignment: .topLeading) {
                ShareCardFrame(canvas: model.layout(in: proxy.size).canvas, stickerness: model.cardShape.stickerness,
                               model: model)

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

private struct ShareCardFrame: View {
    let canvas: CGRect
    let stickerness: CGFloat
    @ObservedObject var model: ShareSheetModel

    var body: some View {
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
