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
        // Reuse a single NSPopover so macOS 26 reuses its popover window & RenderBox surface,
        // while replacing its NSHostingController on every open/close so SwiftUI's AttributeGraph
        // and TypedElement/subgraph caches are torn down completely instead of accumulating.
        let popover: NSPopover
        if let existingPopover = self.popover {
            popover = existingPopover
        } else {
            let createdPopover = NSPopover()
            createdPopover.behavior = .transient
            // Avoids macOS 26 NSPopover fade-out snapshot IOSurfaces (~5 MB RenderBox surfaces).
            createdPopover.animates = false
            createdPopover.delegate = self
            self.popover = createdPopover
            popover = createdPopover
        }
        let host = NSHostingController(rootView: root)
        // Avoid .preferredContentSize live resizing: 1 pt height jitter on macOS 26
        // causes RenderBox to allocate a new non-purgeable IOSurface on every resize tick.
        host.sizingOptions = []
        popover.contentViewController = host
        let maxAllowed = min(maxHeight ?? 680, 680)
        let fittingHeight = host.sizeThatFits(in: NSSize(width: Self.width, height: maxAllowed)).height
        let clampedHeight = min(max(fittingHeight, 240), maxAllowed)
        // Coarse 64 pt quantization prevents macOS 26 RenderBox/Liquid Glass from caching multiple
        // backing surfaces as the agent list grows/shrinks slightly.
        let quantizedHeight = min((clampedHeight / 64).rounded(.up) * 64, maxAllowed)
        let targetSize = NSSize(width: Self.width, height: quantizedHeight)
        if popover.contentSize != targetSize { popover.contentSize = targetSize }
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
        // Flush an empty view while still attached to the popover window so SwiftUI tears down
        // all live observations, animations, and embedded Metal views before close completes.
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
        // Tear down the NSHostingController (destroying SwiftUI's ViewGraph/AttributeGraph) while
        // keeping the NSPopover shell for reuse.
        popover?.contentViewController = nil
        CATransaction.flush()
        onVisibilityChange?(false)
        malloc_zone_pressure_relief(nil, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            malloc_zone_pressure_relief(nil, 0)
        }
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
