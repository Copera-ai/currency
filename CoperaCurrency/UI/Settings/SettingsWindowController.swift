import AppKit
import SwiftUI

/// Manages the standalone Settings window and the activation-policy dance that
/// lets a menu-bar-only (`.accessory`) app present a focusable, Cmd-Tab-able
/// window.
///
/// On `show()` it closes the popover, switches the app to `.regular` (so the
/// window can become key and appear in the Dock / Cmd-Tab), activates, and shows
/// a fixed-size window. On window close it reverts to `.accessory` so no stray
/// Dock icon lingers — proving the policy mechanism that the real Phase-4
/// settings UI will rely on.
///
/// Phase 2 hosts placeholder content; Phase 4 swaps in the real settings root.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Fixed window content size per the design.
    private static let size = NSSize(width: 680, height: 496)

    private let popoverController: PopoverController
    private var window: NSWindow?

    init(popoverController: PopoverController) {
        self.popoverController = popoverController
        super.init()
    }

    /// Show (creating or reusing) the Settings window, taking focus.
    func show() {
        popoverController.close()

        // Become a regular app so the window can take focus + show in Cmd-Tab.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let window = window ?? makeWindow()
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsPlaceholderView()
            // Phase 4 swaps in the real settings root and applies
            // `.themedRoot(settings:)` here so it honors appearance/accent.
        )
        window.setContentSize(Self.size)
        return window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Revert to menu-bar-only so no Dock icon remains.
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Phase-2 placeholder content for the Settings window.
private struct SettingsPlaceholderView: View {
    var body: some View {
        Text("Settings — coming in Phase 4")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
