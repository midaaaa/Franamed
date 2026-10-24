//
//  ShareSheetController.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.10.2026.
//

import Combine
import SwiftUI
import UIKit

final class ShareSheetController: UIHostingController<ShareSheetView> {
    private let model: ShareSheetModel
    private let onLift: () -> Void
    private let onFinish: () -> Void
    private var flight: ShareFlightView?
    private var link: CADisplayLink?
    private var sizeLink: CADisplayLink?
    private var detent: CGFloat?
    private var maximumDetent: CGFloat?
    private var containerSize: CGSize?
    private var resize: Resize?
    private var restTop: CGFloat?
    private var sheetFormat = ShareFormat.story
    private var hasLanded = false
    private var subscriptions: Set<AnyCancellable> = []

    private struct Resize {
        let from: CGFloat
        let to: CGFloat
        let fromShape: ShareCardShape
        let toShape: ShareCardShape
        let start: CFTimeInterval
    }

    private static let topClearance: CGFloat = 10
    private static let landingFade: TimeInterval = 0.2
    private static let sheetSpring = Spring.snappy

    init(model: ShareSheetModel, onLift: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.model = model
        self.onLift = onLift
        self.onFinish = onFinish
        super.init(rootView: ShareSheetView(model: model))
        overrideUserInterfaceStyle = .dark
        modalPresentationStyle = .pageSheet
        configureDetent()
        model.prepareStub()
        model.presentActivity = { [weak self] in self?.presentActivity($0, from: $1) }
        Publishers.Merge(model.$format.dropFirst().map { _ in }, model.$mode.dropFirst().map { _ in })
            .sink { [weak self] in self?.flight?.layer.removeAllAnimations() }
            .store(in: &subscriptions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func present(model: ShareSheetModel, from presenter: UIViewController,
                        onLift: @escaping () -> Void, onFinish: @escaping () -> Void) {
        var top = presenter
        while let presented = top.presentedViewController { top = presented }
        top.present(ShareSheetController(model: model, onLift: onLift, onFinish: onFinish), animated: true)
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 27.1, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (self: Self, _) in
                self.updateBarMode()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBarMode()
        guard isBeingPresented else { return }
        onLift()
        startFlight(entering: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasLanded { restTop = sheetTop() }
        hasLanded = true
        if resize == nil, let maximum = maximumDetent {
            model.sheetHeight = targetDetent(for: sheetFormat, maximum: maximum) + safeBottom
        }
        land()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let size = presentationController?.containerView?.bounds.size, size != containerSize {
            containerSize = size
            model.updateStubWidth(windowSize: size)
            sheetPresentationController?.invalidateDetents()
        }
        guard hasLanded, resize == nil, !isBeingDismissed, let maximum = maximumDetent else { return }
        let height = targetDetent(for: sheetFormat, maximum: maximum) + safeBottom
        guard height != model.sheetHeight else { return }
        model.sheetHeight = height
        sheetPresentationController?.invalidateDetents()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isBeingDismissed else { return }
        startFlight(entering: false)
        model.showsStub = false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed else { return }
        stopLink()
        stopSizeLink()
        onFinish()
        removeFlight()
    }

    private func updateBarMode() {
        guard #available(iOS 27.1, *) else { return }
        let usesBar = traitCollection.verticalBarEdge != .unspecified
        guard usesBar != model.usesBar else { return }
        model.usesBar = usesBar
        sheetPresentationController?.invalidateDetents()
    }

    // MARK: Activity

    private func presentActivity(_ items: [Any], from source: CGRect) {
        guard presentedViewController == nil else { return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            if completed { self?.dismiss(animated: true) }
        }
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = source.offsetBy(dx: contentLeft, dy: 0)
        present(activity, animated: true)
    }

    // MARK: Size

    private func configureDetent() {
        guard let sheet = sheetPresentationController else { return }
        sheetFormat = model.format
        sheet.detents = [.custom(identifier: .init("share")) { [weak self] context in
            guard let self else { return context.maximumDetentValue }
            let maximum = context.maximumDetentValue - safeArea.top - Self.topClearance
            maximumDetent = maximum
            return min(maximum, detent ?? targetDetent(for: sheetFormat, maximum: maximum))
        }]
        model.onFormatChange = { [weak self] in self?.resizeSheet(to: $0) }
    }

    private var safeArea: UIEdgeInsets { window?.safeAreaInsets ?? .zero }

    private var safeBottom: CGFloat { safeArea.bottom }

    private func targetDetent(for format: ShareFormat, maximum: CGFloat) -> CGFloat {
        let width = isViewLoaded && view.bounds.width > 0 ? contentWidth(of: view.bounds.width)
                                                          : model.material.roundSize.width
        let fitted = ShareSheetLayout.fittedHeight(width: width, panelHeight: model.panelHeight(for: format),
                                                   format: format, stubWidth: model.stubWidth)
        return min(maximum, fitted - safeBottom)
    }

    private func contentWidth(of width: CGFloat) -> CGFloat {
        guard let scale = contentScale(width) else { return width - view.safeAreaInsets.left - view.safeAreaInsets.right }
        return model.contentFrame.width * scale
    }

    private var contentLeft: CGFloat {
        guard let scale = contentScale(view.bounds.width) else { return view.safeAreaInsets.left }
        return (model.contentFrame.minX - model.rootFrame.minX) * scale
    }

    private func contentScale(_ width: CGFloat) -> CGFloat? {
        guard model.contentFrame.width > 0, model.rootFrame.width > 0 else { return nil }
        return width / model.rootFrame.width
    }

    private func resizeSheet(to format: ShareFormat) {
        sheetFormat = format
        guard hasLanded, !isBeingDismissed, let maximum = maximumDetent else {
            model.cardShape = model.cardShape(for: format)
            return
        }
        let from = detent ?? view.bounds.height - safeBottom
        resize = Resize(from: from, to: targetDetent(for: format, maximum: maximum), fromShape: model.cardShape,
                        toShape: model.cardShape(for: format), start: CACurrentMediaTime())
        isModalInPresentation = true
        guard sizeLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(sizeTick))
        link.add(to: .main, forMode: .common)
        sizeLink = link
        sizeTick()
    }

    @objc private func sizeTick() {
        guard let resize, let sheet = sheetPresentationController else { return stopSizeLink() }
        let time = CACurrentMediaTime() - resize.start
        let isDone = time >= Self.sheetSpring.settlingDuration
        let progress = isDone ? 1 : Self.sheetSpring.value(target: 1.0, time: time)
        let grid = PixelGrid(displayScale: traitCollection.displayScale)
        let height = grid.snapped(resize.from + (resize.to - resize.from) * progress)
        detent = isDone ? nil : height
        model.cardShape = resize.fromShape.mixed(with: resize.toShape, by: progress)
        model.sheetHeight = height + safeBottom
        sheet.invalidateDetents()
        guard isDone else { return }
        self.resize = nil
        stopSizeLink()
        isModalInPresentation = false
    }

    private func stopSizeLink() {
        sizeLink?.invalidate()
        sizeLink = nil
    }

    // MARK: Flight

    private var window: UIWindow? {
        view.window ?? presentingViewController?.view.window
    }

    private func startFlight(entering: Bool) {
        guard let window else { return }
        if restTop == nil, let frame = presentationController?.frameOfPresentedViewInContainerView,
           let container = presentationController?.containerView {
            restTop = container.convert(frame, to: window).minY
        }
        flight?.removeFromSuperview()
        guard let renderer = model.launch.makeFlight() else { return }
        model.isFlying = true
        let flight = ShareFlightView(flight: renderer, shareFace: model.faceTexture(), shadow: model.shadowImage(),
                                     shadowStubWidth: model.material.stubWidth, entering: entering)
        window.addSubview(flight)
        self.flight = flight
        stopLink()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        tick()
    }

    @objc private func tick() {
        if isBeingPresented, !hasLanded, view.layer.presentation() != nil {
            restTop = view.convert(CGPoint.zero, to: nil).y
        }
        if hasLanded, let sheetHeight = model.sheetHeight, let window {
            restTop = window.bounds.height - sheetHeight
        }
        guard let window, let flight, let restTop else { return }
        let top = sheetTop() ?? window.bounds.height
        let travel = max(window.bounds.height - restTop, 1)
        let progress = 1 - min(max((top - restTop) / travel, 0), 1)
        let size = view.layer.presentation()?.bounds.size ?? view.bounds.size
        let layout = model.layout(in: CGSize(width: contentWidth(of: size.width), height: size.height))
            .offsetBy(dx: contentLeft, dy: 0)
        let target = onScreen(layout.stub) ?? layout.stub.offsetBy(dx: 0, dy: top)
        flight.update(progress: progress, source: model.launch.currentSource(), target: target,
                      angle: CGFloat(layout.angle.radians), turnsFromBack: model.launch.startsOnBack)
    }

    private func sheetTop() -> CGFloat? {
        guard let window else { return nil }
        guard let layer = view.layer.presentation() else {
            return isBeingPresented ? window.bounds.height : restTop
        }
        let space = window.layer.presentation() ?? window.layer
        return layer.convert(CGPoint.zero, to: space).y
    }

    private func onScreen(_ rect: CGRect) -> CGRect? {
        guard let window, let layer = view.layer.presentation() else { return nil }
        return layer.convert(rect, to: window.layer.presentation() ?? window.layer)
    }

    private func land() {
        guard let flight else { stopLink(); return }
        model.showsStub = true
        model.isFlying = false
        flight.land()
        DispatchQueue.main.async { [model] in model.prepareStub(for: .riddle) }
        UIView.animate(withDuration: Self.landingFade, delay: 0, options: [.beginFromCurrentState]) {
            flight.alpha = 0
        } completion: { [weak self] _ in
            guard let self, self.flight === flight else { return }
            self.stopLink()
            self.removeFlight()
        }
    }

    private func removeFlight() {
        guard let flight else { return }
        self.flight = nil
        model.isFlying = false
        DispatchQueue.main.async {
            DispatchQueue.main.async { flight.removeFromSuperview() }
        }
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }
}
