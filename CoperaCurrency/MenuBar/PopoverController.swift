import AppKit
import SwiftUI

/// The single popover shared by every status item. It re-anchors to whichever item
/// was clicked and sizes itself from the SwiftUI content (rows expand in place).
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let model: AppModel
    private weak var anchor: NSStatusBarButton?
    /// Opened with the global shortcut: focus the amount once the popover is key.
    private var focusesAmount = false
    private var activationObserver: (any NSObjectProtocol)?

    init(model: AppModel) {
        self.model = model
        super.init()
        let host = NSHostingController(rootView: PopoverView().environment(model).environment(model.store))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // Activation is asynchronous (and cooperative): make the popover key once it lands.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.takeKeyFocus() }
        }
    }

    var isShown: Bool { popover.isShown }

    /// Applies the user's Light/Dark choice to the popover only (never to the menu bar).
    func setAppearance(_ appearance: NSAppearance?) {
        popover.appearance = appearance
    }

    /// A click on the anchored item while the popover is open closes it. The transient
    /// popover does not close on that item's mouse down (see ``popoverShouldClose(_:)``),
    /// so the click's mouse up sees it still shown.
    func toggle(from button: NSStatusBarButton) {
        if popover.isShown, anchor === button {
            close()
        } else {
            show(from: button)
        }
    }

    /// Shows the popover under `button`. `focusingAmount` (global shortcut) puts the
    /// keyboard focus in the converter's amount field.
    func show(from button: NSStatusBarButton, focusingAmount: Bool = false) {
        if popover.isShown, anchor !== button { popover.close() }
        anchor?.highlight(false)
        anchor = button
        focusesAmount = focusingAmount
        // An accessory app must be active for the popover to take keyboard focus. From a
        // status item click or the global shortcut this is a response to user input, which
        // cooperative activation honors; `takeKeyFocus()` runs again once it lands.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        takeKeyFocus()
    }

    func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// Makes the popover window key and, when requested, focuses the amount field.
    private func takeKeyFocus() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        window.makeKey()
        guard focusesAmount else { return }
        model.amountFocusRequest += 1
        // Keep asking until the app is actually active (the field can't take typing before).
        if NSApp.isActive { focusesAmount = false }
    }

    // MARK: - NSPopoverDelegate

    /// Keeps the transient popover open on a mouse down on its own anchor item: the
    /// item's mouse up then toggles it closed instead of closing and reopening it.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard let anchor, let event = NSApp.currentEvent, event.type == .leftMouseDown,
              !event.modifierFlags.contains(.control), event.window === anchor.window
        else { return true }
        return !anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
    }

    func popoverWillShow(_ notification: Notification) {
        model.isPopoverShown = true
    }

    func popoverDidShow(_ notification: Notification) {
        takeKeyFocus()
    }

    func popoverDidClose(_ notification: Notification) {
        // A close of the previous anchor can land after the popover re-opened elsewhere.
        guard !popover.isShown else { return }
        anchor?.highlight(false)
        focusesAmount = false
        model.isPopoverShown = false
        model.pickerSide = nil
    }
}
