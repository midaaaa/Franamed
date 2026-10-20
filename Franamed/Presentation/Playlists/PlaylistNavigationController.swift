//
//  PlaylistNavigationController.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 17.10.2026.
//

import Combine
import SwiftUI
import UIKit

final class PlaylistNavigationController: UINavigationController {
    private let playlists: PlaylistsViewModel
    private let mediaType: MediaType
    private let onDone: () -> Void
    private let flight = PlaylistFlightState()
    private let query = PlaylistShelfQuery()
    private var popInteraction: UIPercentDrivenInteractiveTransition?
    private var trackLink: CADisplayLink?
    private var sampleFlight: (() -> PlaylistFlightSample)?
    private(set) var isTransitioning = false {
        didSet {
            guard isTransitioning != oldValue else { return }
            view.subviews.forEach { $0.isUserInteractionEnabled = !isTransitioning }
        }
    }
    var settledBottomInset: CGFloat = 0
    private lazy var popPan = UIPanGestureRecognizer(target: self, action: #selector(handlePopPan(_:)))
    private let selectWidths = NSHashTable<NSLayoutConstraint>.weakObjects()

    private static let revealMargin: CGFloat = 12
    private static let selectInset: CGFloat = 24
    private static let selectHeight: CGFloat = 52
    private static let toolbarMinBottomGap: CGFloat = 16
    private static let selectMaxWidth: CGFloat = 480
    private static let popFinishProgress: CGFloat = 0.4
    private static let popFinishVelocity: CGFloat = 500

    init(playlists: PlaylistsViewModel, mediaType: MediaType, openedID: String?, onDone: @escaping () -> Void) {
        self.playlists = playlists
        self.mediaType = mediaType
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
        flight.openID = openedID
        delegate = self
        var controllers = [makeShelf(revealID: openedID == nil ? playlists.selectedID(for: mediaType) : nil)]
        if let openedID { controllers.append(makeDetail(openedID)) }
        setViewControllers(controllers, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.isEnabled = false
        interactiveContentPopGestureRecognizer?.isEnabled = false
        setToolbarHidden(false, animated: false)
        popPan.delegate = self
        view.addGestureRecognizer(popPan)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        let systemBottom = view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom
        let extra = max(0, Self.toolbarMinBottomGap - systemBottom)
        if additionalSafeAreaInsets.bottom != extra { additionalSafeAreaInsets.bottom = extra }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = Self.selectWidth(in: view.bounds.width)
        for constraint in selectWidths.allObjects where constraint.constant != width {
            constraint.constant = width
        }
    }

    private static func selectWidth(in containerWidth: CGFloat) -> CGFloat {
        min(selectMaxWidth, containerWidth - 2 * selectInset)
    }

    // MARK: Screens

    private func makeShelf(revealID: String?) -> UIViewController {
        let flight = flight
        let root = PlaylistShelfView(playlists: playlists, mediaType: mediaType, flight: flight, query: query,
                                     revealID: revealID) { [weak self] id in self?.open(id) }
        let host = PlaylistHost(rootView: AnyView(root))
        host.view.backgroundColor = .clear
        host.clampsScroll = true
        let item = host.navigationItem
        item.title = "Подборки"
        item.largeTitleDisplayMode = .never
        item.backButtonDisplayMode = .minimal
        item.leftBarButtonItem = sortItem()
        item.rightBarButtonItem = closeItem()
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Название подборки"
        item.searchController = search
        item.preferredSearchBarPlacement = .integratedButton
        host.pinnedToolbarItems = [.flexibleSpace(), item.searchBarPlacementBarButtonItem]
        return host
    }

    private func makeDetail(_ id: String) -> UIViewController {
        playlists.noteOpened(id)
        let flight = flight
        let root = PlaylistDetailView(playlists: playlists, playlistID: id, flight: flight)
        let host = PlaylistHost(rootView: AnyView(root))
        host.playlistID = id
        host.view.backgroundColor = .clear
        host.navigationItem.largeTitleDisplayMode = .never
        host.navigationItem.rightBarButtonItem = closeItem()
        host.pinnedToolbarItems = selectItems(for: id)
        return host
    }

    private func selectItems(for id: String) -> [UIBarButtonItem] {
        guard let playlist = playlists.playlist(id: id) else { return [] }
        let isSelected = playlists.isSelected(id)
        var configuration = isSelected ? UIButton.Configuration.glass() : UIButton.Configuration.prominentGlass()
        configuration.title = isSelected ? "Выбрана" : "Выбрать"
        if isSelected {
            configuration.image = UIImage(systemName: "checkmark")
            configuration.imagePadding = 6
            configuration.baseForegroundColor = .secondaryLabel
        } else {
            configuration.baseBackgroundColor = UIColor(Accent.action)
            configuration.baseForegroundColor = UIColor(Accent.actionForeground)
        }
        configuration.buttonSize = .large
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .headline)
            return attributes
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.playlists.select(id)
            self?.onDone()
        })
        button.isEnabled = isSelected || playlist.availableCount > 0
        button.isUserInteractionEnabled = !isSelected
        let width = button.widthAnchor.constraint(equalToConstant: Self.selectMaxWidth)
        selectWidths.add(width)
        NSLayoutConstraint.activate([
            width,
            button.heightAnchor.constraint(equalToConstant: Self.selectHeight),
        ])
        let item = UIBarButtonItem(customView: button)
        item.hidesSharedBackground = true
        return [.flexibleSpace(), item, .flexibleSpace()]
    }

    private func closeItem() -> UIBarButtonItem {
        UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onDone() })
    }

    private func sortItem() -> UIBarButtonItem {
        let options = UIDeferredMenuElement.uncached { completion in
            let defaults = UserDefaults.standard
            let current = defaults.string(forKey: PlaylistSort.storageKey).flatMap(PlaylistSort.init) ?? .started
            completion(PlaylistSort.allCases.map { option in
                UIAction(title: option.title, state: option == current ? .on : .off) { _ in
                    defaults.set(option.rawValue, forKey: PlaylistSort.storageKey)
                }
            })
        }
        return UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"), menu: UIMenu(children: [options]))
    }

    // MARK: Flight

    private func open(_ id: String) {
        guard transitionCoordinator == nil, viewControllers.count == 1 else { return }
        pushViewController(makeDetail(id), animated: true)
    }

    private var shelfScroll: UIScrollView? {
        (viewControllers.first as? PlaylistHost)?.scrollView
    }

    private func revealShelf(at id: String) {
        guard let scroll = shelfScroll, let folder = flight.folderFrames[id] else { return }
        let rect = flight.cellFrames[id] ?? folder
        var inset = scroll.adjustedContentInset
        inset.bottom = max(inset.bottom, settledBottomInset)
        var y = scroll.contentOffset.y
        let top = y + inset.top + Self.revealMargin
        let bottom = y + scroll.bounds.height - inset.bottom - Self.revealMargin
        if rect.minY < top {
            y -= top - rect.minY
        } else if rect.maxY > bottom {
            y += rect.maxY - bottom
        }
        let maxY = max(scroll.contentSize.height + inset.bottom - scroll.bounds.height, -inset.top)
        y = min(max(y, -inset.top), maxY)
        scroll.contentOffset.y = y
    }

    private func flightPlan(for id: String, in container: UIView, isPush: Bool) -> PlaylistFlightPlan? {
        if !isPush { revealShelf(at: id) }
        guard let playlist = playlists.playlist(id: id), let scroll = shelfScroll,
              let folder = flight.folderFrames[id], let header = flight.headerFrames[id] else { return nil }
        let folderRect = container.convert(folder, from: scroll)
        let headerRect = container.convert(header, from: nil)
        guard folderRect.intersects(container.bounds) else { return nil }
        let posters = playlist.folderPosters(count: PlaylistFolderCover.posterCount)
        return PlaylistFlightPlan(
            images: posters.map { $0.flatMap(ImageCache.shared.image(for:)) },
            folder: PlaylistFolderCover.posterSlots(count: posters.count, in: folderRect.size, isOpen: false)
                .map { $0.offset(by: folderRect.origin) },
            header: PlaylistPosterFan.layout(count: posters.count, zoom: headerZoom(width: headerRect.width, count: posters.count))
                .slots.map { $0.offset(by: headerRect.origin) },
            frontTop: folderRect.minY + PlaylistFolderCover.frontTop(in: folderRect.size, isOpen: true)
        )
    }

    private func headerZoom(width: CGFloat, count: Int) -> CGFloat {
        let base = PlaylistPosterFan.layout(count: count).size.width
        return base > 0 ? width / base : 1
    }

    private func startFlight(id: String, sample: (() -> PlaylistFlightSample)?) {
        flight.openID = id
        guard let sample else { return }
        flight.flyingID = id
        sampleFlight = sample
        apply(sample())
        let link = CADisplayLink(target: self, selector: #selector(stepFlight))
        link.add(to: .main, forMode: .common)
        trackLink = link
    }

    @objc private func stepFlight() {
        if let sample = sampleFlight?() { apply(sample) }
    }

    private func apply(_ sample: PlaylistFlightSample) {
        guard let id = flight.flyingID, let folder = flight.folderFrames[id], let scroll = shelfScroll else { return }
        let origin = scroll.convert(folder.origin, to: nil)
        flight.track.slots = sample.slots.map { $0.offset(by: CGPoint(x: -origin.x, y: -origin.y)) }
        if flight.track.isCopyShown != sample.isCopyShown { flight.track.isCopyShown = sample.isCopyShown }
    }

    private func finishFlight() {
        trackLink?.invalidate()
        trackLink = nil
        sampleFlight = nil
        flight.track.slots = nil
        flight.track.isCopyShown = false
        flight.flyingID = nil
        if viewControllers.count == 1 { flight.openID = nil }
    }

    @objc private func handlePopPan(_ pan: UIPanGestureRecognizer) {
        let progress = min(max(pan.translation(in: view).x / max(view.bounds.width, 1), 0), 1)
        switch pan.state {
        case .began:
            let interaction = UIPercentDrivenInteractiveTransition()
            interaction.timingCurve = PlaylistFlightAnimator.timing
            popInteraction = interaction
            popViewController(animated: true)
        case .changed:
            popInteraction?.update(progress)
        case .ended, .cancelled, .failed:
            let velocity = pan.velocity(in: view).x
            let finishes = pan.state == .ended
                && (velocity > Self.popFinishVelocity || (progress > Self.popFinishProgress && velocity > -100))
            if finishes {
                popInteraction?.finish()
            } else {
                popInteraction?.cancel()
            }
            popInteraction = nil
        default:
            break
        }
    }
}

extension PlaylistNavigationController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController,
                              animated: Bool) {
        isTransitioning = animated
        transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] _ in self?.isTransitioning = false }
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController,
                              animated: Bool) {
        isTransitioning = false
    }

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController,
                              to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        let isPush = operation == .push
        guard operation != .none, let detail = (isPush ? toVC : fromVC) as? PlaylistHost,
              let id = detail.playlistID else { return nil }
        return PlaylistFlightAnimator(
            isPush: isPush,
            plan: { [weak self] container in self?.flightPlan(for: id, in: container, isPush: isPush) },
            onStart: { [weak self] sample in self?.startFlight(id: id, sample: sample) },
            onEnd: { [weak self] in self?.finishFlight() }
        )
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning)
        -> (any UIViewControllerInteractiveTransitioning)? {
        popInteraction
    }
}

extension PlaylistNavigationController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === popPan else { return true }
        guard viewControllers.count > 1, transitionCoordinator == nil else { return false }
        let velocity = popPan.velocity(in: view)
        return velocity.x > abs(velocity.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === popPan && otherGestureRecognizer.view is UIScrollView
    }
}

extension PlaylistNavigationController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        query.text = searchController.searchBar.text ?? ""
    }
}
