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
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ShareCardFrame(canvas: model.layout(in: proxy.size).canvas,
                                   stickerness: model.cardShape.stickerness, model: model)

                    SharePanel(material: model.material, mode: $model.mode, background: $model.background,
                               format: $model.format, showsShareButton: !model.usesBar, onShare: model.send)
                        .frame(width: proxy.size.width, height: model.tallestPanel, alignment: .bottom)
                        .allowsHitTesting(!model.isFlying)
                        .offset(y: ShareSheetLayout.panelTop(height: proxy.size.height,
                                                             panelHeight: model.tallestPanel))
                }
                .coordinateSpace(.named(ShareSheetLayout.coordinateSpace))
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.contentFrame = $0 }
            .ignoresSafeArea(edges: .vertical)
            .toolbar {
                if model.usesBar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Поделиться", systemImage: "square.and.arrow.up") { model.send(from: .zero) }
                            .disabled(model.isFlying)
                    }
                }
            }
            .toolbarVisibility(model.usesBar ? .visible : .hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .containerBackground(.clear, for: .navigation)
        }
        .background {
            Color.clear
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.rootFrame = $0 }
                .ignoresSafeArea()
        }
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
