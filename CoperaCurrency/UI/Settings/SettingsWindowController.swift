import AppKit
import SwiftUI

/// Manages the standalone Settings window and the activation-policy dance that
/// lets a menu-bar-only (`.accessory`) app present a focusable, Cmd-Tab-able
/// window.
///
/// On `show()` it closes the popover, switches the app to `.regular` (so the
/// window can become key and appear in the Dock / Cmd-Tab), activates, and shows
/// the fixed-size Settings window. On window close it reverts to `.accessory` so
/// no stray Dock icon lingers.
///
/// `show(tab:)` deep-links to a specific section: the popover gear / "Settings…"
/// open General, while "Manage" opens Currencies. The last-shown tab is
/// remembered so a plain `show()` returns to where the user left off.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Fixed window content size per the design.
    private static let size = NSSize(width: 680, height: 496)

    private let store: RatesStore
    private let settings: AppSettings
    private let popoverController: PopoverController

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    /// Remembered so a plain `show()` reopens the last-viewed section.
    private var lastTab: SettingsTab = .general

    init(store: RatesStore, settings: AppSettings, popoverController: PopoverController) {
        self.store = store
        self.settings = settings
        self.popoverController = popoverController
        super.init()
    }

    /// Show the Settings window, returning to the last-viewed tab.
    func show() { show(tab: lastTab) }

    /// Show (creating or reusing) the Settings window, deep-linking to `tab`.
    func show(tab: SettingsTab) {
        popoverController.close()
        lastTab = tab

        // Become a regular app so the window can take focus + show in Cmd-Tab.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let window = window ?? makeWindow()
        self.window = window

        // Update the hosted root so a reused window jumps to the requested tab.
        hostingController?.rootView = rootView(tab: tab)

        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func rootView(tab: SettingsTab) -> AnyView {
        AnyView(
            SettingsRoot(store: store, settings: settings, initialTab: tab)
                .themedRoot(settings: settings)
        )
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: rootView(tab: lastTab))
        self.hostingController = host

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = host
        window.setContentSize(Self.size)
        // Fixed-size, non-resizable per the design.
        window.styleMask.remove(.resizable)
        return window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Revert to menu-bar-only so no Dock icon remains.
        NSApp.setActivationPolicy(.accessory)
    }
}
