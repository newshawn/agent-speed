import AppKit
import Darwin
import SwiftUI

/// The native settings window: toolbar tabs, one grouped form per pane, sized to the selected pane.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let lastPaneKey = "settings.lastPane"

    private let model: AppModel
    private var window: SettingsWindow?
    private var tabs: SettingsTabViewController?
    private var hasCentered = false
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.isVisible == true else { return }
                self.model.launchAtLogin.refresh()
            }
        }
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    /// Shows the window on `pane`, or on the last pane the user looked at when nil.
    func show(pane: SettingsPane?) {
        let (window, tabs) = ensureWindow()
        let target = pane ?? storedPane ?? .general
        model.launchAtLogin.refresh()
        tabs.select(target)
        if !window.isVisible {
            window.contentView?.layoutSubtreeIfNeeded()
            tabs.fitWindowToSelectedPane(animated: false)
            if !hasCentered {
                window.center()
                hasCentered = true
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if !NSApp.isActive { window.orderFrontRegardless() }
    }

    private var storedPane: SettingsPane? {
        UserDefaults.standard.string(forKey: Self.lastPaneKey).flatMap(SettingsPane.init(rawValue:))
    }

    private func ensureWindow() -> (SettingsWindow, SettingsTabViewController) {
        if let window, let tabs { return (window, tabs) }
        let tabs = SettingsTabViewController(model: model)
        tabs.onSelect = { pane in
            UserDefaults.standard.set(pane.rawValue, forKey: Self.lastPaneKey)
        }
        tabs.select(storedPane ?? .general)

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsPaneView.width, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.contentViewController = tabs
        window.delegate = self
        window.toolbarStyle = .preference
        window.titleVisibility = .visible
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.onQuit = { [weak model] in model?.commands?.quit() }
        tabs.applyTitles()

        self.window = window
        self.tabs = tabs
        return (window, tabs)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        tabs?.stop()
        closing.delegate = nil
        closing.contentViewController = nil
        tabs = nil
        window = nil
        hasCentered = false
        malloc_zone_pressure_relief(nil, 0)
    }
}
