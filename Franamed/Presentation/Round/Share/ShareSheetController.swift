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
    private var restTop: CGFloat?
    private var hasLanded = false
    private var subscriptions: Set<AnyCancellable> = []

    private static let topClearance: CGFloat = 10
    private static let landingFade: TimeInterval = 0.2

    init(model: ShareSheetModel, onLift: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.model = model
        self.onLift = onLift
        self.onFinish = onFinish
        super.init(rootView: ShareSheetView(model: model))
        overrideUserInterfaceStyle = .dark
        modalPresentationStyle = .pageSheet
        configureDetent()
        model.prepareStub()
        model.presentActivity = { [weak self] in self?.presentActivity($0) }
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isBeingPresented else { return }
        onLift()
        startFlight(entering: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasLanded { restTop = sheetTop() }
        hasLanded = true
        land()
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
        onFinish()
        removeFlight()
    }

    // MARK: Activity

    private func presentActivity(_ items: [Any]) {
        guard presentedViewController == nil else { return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            if completed { self?.dismiss(animated: true) }
        }
        present(activity, animated: true)
    }

    // MARK: Size

    private func configureDetent() {
        guard let sheet = sheetPresentationController else { return }
        let safeArea = WindowMetrics.safeAreaInsets
        let clearance = safeArea.top + Self.topClearance
        sheet.detents = [.custom(identifier: .init("share")) { [weak model] context in
            let maximum = context.maximumDetentValue - clearance
            guard let model else { return maximum }
            model.maxSheetHeight = maximum + safeArea.bottom
            let fitted = ShareSheetLayout.fittedHeight(width: WindowMetrics.size.width, panelHeight: model.panelHeight,
                                                       format: model.format)
            return min(maximum, fitted - safeArea.bottom)
        }]
        model.$format.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.resizeSheet() } }
            .store(in: &subscriptions)
    }

    private func resizeSheet() {
        guard let sheet = sheetPresentationController, hasLanded, !isBeingDismissed else { return }
        sheet.animateChanges { sheet.invalidateDetents() }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isBeingDismissed, let window = self.view.window else { return }
            self.restTop = self.view.convert(CGPoint.zero, to: window).y
        }
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
                                     entering: entering)
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
        guard let window, let flight, let restTop else { return }
        let top = sheetTop() ?? window.bounds.height
        let travel = max(window.bounds.height - restTop, 1)
        let progress = 1 - min(max((top - restTop) / travel, 0), 1)
        let layout = model.layout(in: view.layer.presentation()?.bounds.size ?? view.bounds.size)
        let target = onScreen(layout.stub) ?? layout.stub.offsetBy(dx: 0, dy: top)
        flight.update(progress: progress, source: model.launch.source, target: target,
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
