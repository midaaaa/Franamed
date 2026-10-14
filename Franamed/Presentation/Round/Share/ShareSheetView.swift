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
                ShareCardFrame(canvas: model.layout(in: proxy.size).canvas, stickerness: model.format == .sticker ? 1 : 0,
                               model: model)
                    .animation(.snappy, value: model.format)

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
    var canvas: CGRect
    var stickerness: CGFloat
    @ObservedObject var model: ShareSheetModel

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>, CGFloat> {
        get {
            AnimatablePair(AnimatablePair(AnimatablePair(canvas.minX, canvas.minY),
                                          AnimatablePair(canvas.width, canvas.height)), stickerness)
        }
        set {
            let rect = newValue.first
            canvas = CGRect(x: rect.first.first, y: rect.first.second,
                            width: rect.second.first, height: rect.second.second)
            stickerness = newValue.second
        }
    }

    var body: some View {
        let scale = canvas.width / ShareFormat.baseWidth
        ShareCard(material: model.material, mode: model.mode, background: model.shownBackground, format: model.format,
                  showsStub: model.showsStub, cornerRadius: ShareSheetLayout.cardCornerRadius / scale,
                  height: canvas.height / scale, stickerness: stickerness)
            .scaleEffect(scale, anchor: .topLeading)
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
