import AppKit
import Darwin
import SwiftUI

/// Hosts the dashboard in a transient popover anchored to the status item.
@MainActor
final class DashboardController: NSObject, NSPopoverDelegate {
    static let width: CGFloat = 368

    /// Room kept free between the popover and the screen's visible edges (arrow included).
    private static let screenMargin: CGFloat = 28

    private let model: AppModel
    private var popover: NSPopover?
    /// The agent rows' score cards, alive while the panel is open.
    private var scoreCards: DashboardScoreCards?
    private var closedAt: TimeInterval = 0
    private var appearanceObservation: NSKeyValueObservation?
    var onVisibilityChange: ((Bool) -> Void)?

    init(model: AppModel) {
        self.model = model
    }

    var isShown: Bool { popover?.isShown ?? false }

    #if DEBUG
    var debugPopover: NSPopover? { popover }
    #endif

    func toggle(relativeTo view: NSView) {
        if isShown {
            close()
        } else if Clock.now - closedAt > 0.15 {
            show(relativeTo: view)
        }
    }

    func show(relativeTo view: NSView) {
        guard !isShown else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        // Avoids macOS 26 NSPopover fade-out snapshot IOSurfaces (~5 MB RenderBox surfaces).
        popover.animates = false
        popover.delegate = self
        let cards = DashboardScoreCards(model: model)
        scoreCards = cards
        let maxHeight = Self.maxHeight(below: view)
        let root = AnyView(
            DashboardView(model: model, maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .environment(\.dashboardScoreCards, cards)
                .appEnvironment(model)
        )
        let host = NSHostingController(rootView: root)
        // Avoid .preferredContentSize live resizing: 1 pt height jitter (e.g. 1718 <-> 1720 px) on macOS 26
        // causes RenderBox to allocate a new 5 MB non-purgeable IOSurface on every resize tick.
        host.sizingOptions = []
        let fittingHeight = host.sizeThatFits(in: NSSize(width: Self.width, height: maxHeight ?? 760)).height
        let clampedHeight = min(max(fittingHeight, 240), maxHeight ?? 760)
        let quantizedHeight = (clampedHeight / 8).rounded(.up) * 8
        popover.contentSize = NSSize(width: Self.width, height: quantizedHeight)
        popover.contentViewController = host
        self.popover = popover
        applyAppearance()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
        NSApp.activate()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        onVisibilityChange?(true)
    }

    func close() {
        popover?.performClose(nil)
    }

    func popoverWillClose(_ notification: Notification) {
        scoreCards?.close()
        // Flush an empty view while still attached to the popover window so SwiftUI/RenderBox
        // drops its RB::Surface backing IOSurface before teardown.
        if let host = popover?.contentViewController as? NSHostingController<AnyView> {
            host.rootView = AnyView(EmptyView())
            host.view.layoutSubtreeIfNeeded()
            host.view.displayIfNeeded()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        scoreCards?.close()
        scoreCards = nil
        appearanceObservation = nil
        closedAt = Clock.now
        if let host = popover?.contentViewController as? NSHostingController<AnyView> {
            host.rootView = AnyView(EmptyView())
            host.view.removeFromSuperview()
        }
        popover?.contentViewController = nil
        popover?.delegate = nil
        popover = nil
        onVisibilityChange?(false)
        malloc_zone_pressure_relief(nil, 0)
    }

    /// A popover takes its appearance from the menu bar it hangs from, which on macOS 26 follows the desktop picture
    /// rather than the app. The dashboard follows the app's Appearance setting (and the system under Auto) instead.
    private func applyAppearance() {
        guard let popover else { return }
        let wanted: NSAppearance?
        if let chosen = NSApp.appearance {
            wanted = chosen
        } else if #available(macOS 26, *) {
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            wanted = NSAppearance(named: dark ? .darkAqua : .aqua)
        } else {
            wanted = nil
        }
        if popover.appearance?.name != wanted?.name { popover.appearance = wanted }
    }

    /// Height available under the anchor on its screen, so the popover never runs off the bottom edge.
    private static func maxHeight(below view: NSView) -> CGFloat? {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return nil }
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        let available = anchor.minY - screen.visibleFrame.minY - screenMargin
        return available > 240 ? available : nil
    }
}
