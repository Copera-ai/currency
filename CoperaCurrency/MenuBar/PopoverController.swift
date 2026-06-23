import AppKit
import SwiftUI

/// Owns the single shared transient ``NSPopover`` used by every status item.
///
/// One popover is reused across all status items: `toggle(relativeTo:)` shows it
/// anchored to a button, hides it if it's already shown for that same button, or
/// moves it when a different button is clicked. The anchored button is
/// highlighted while the popover is open and un-highlighted on close (via the
/// popover delegate).
///
/// Phase 3 hosts the real ``PopoverView``. The content is an
/// `NSHostingController` whose SwiftUI tree drives the popover's intrinsic height
/// (368 wide) via `sizingOptions = .preferredContentSize`.
///
/// Vibrancy: the `NSPopover` already provides a vibrant backing, and the SwiftUI
/// `PanelBackground` layers `.ultraThinMaterial` (or a solid fill when reduce-
/// transparency is on) over it. This matches the design's translucent panel
/// without the auto-sizing fragility of wrapping the hosting view in a manual
/// `NSVisualEffectView` container.
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    /// Fixed popover width per the design (intrinsic height).
    static let width: CGFloat = 368

    private let popover: NSPopover
    private let store: RatesStore
    private let settings: AppSettings
    /// Opens the Settings window (threaded in from `AppDelegate`, since the
    /// popover can't reach `SettingsWindowController` directly). Closes the
    /// popover before opening.
    private let onOpenSettings: () -> Void

    /// The button the popover is currently anchored to (for highlight bookkeeping).
    private weak var anchorButton: NSStatusBarButton?

    init(store: RatesStore, settings: AppSettings, onOpenSettings: @escaping () -> Void = {}) {
        self.store = store
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = makeContentController()
    }

    /// Build the hosting controller for the real popover UI. The popover is sized
    /// from the SwiftUI content's intrinsic size (width pinned to ``width``).
    private func makeContentController() -> NSViewController {
        let root = PopoverView(
            store: store,
            settings: settings,
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        .themedRoot(settings: settings)

        let hosting = NSHostingController(rootView: root)
        // Drive the popover's height from the SwiftUI content's intrinsic size.
        hosting.sizingOptions = [.preferredContentSize]
        return hosting
    }

    /// Close the popover, then open Settings.
    private func openSettings() {
        close()
        onOpenSettings()
    }

    /// Show or hide the popover relative to the given status-item button.
    ///
    /// - Already shown for this button → close.
    /// - Shown for a different button → move (close, re-anchor, reopen).
    /// - Hidden → show anchored to this button.
    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            if anchorButton === button {
                close()
                return
            }
            close()
        }
        show(relativeTo: button)
    }

    private func show(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        button.highlight(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Close the popover if shown (e.g. before opening the Settings window).
    func close() {
        if popover.isShown {
            popover.performClose(nil)
        }
        anchorButton?.highlight(false)
        anchorButton = nil
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        // Transient dismissal (click-outside, Esc) routes here too; drop the
        // active button highlight.
        anchorButton?.highlight(false)
        anchorButton = nil
    }
}
