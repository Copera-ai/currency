import AppKit
import SwiftUI

/// Wraps a single ``NSStatusItem`` representing one tracked currency pair.
///
/// The status-item button hosts an ``StatusItemLabelView`` (via `NSHostingView`)
/// pinned to the button with Auto Layout, so SwiftUI drives the item's intrinsic
/// width while the height fits the menu-bar thickness. Left-click toggles the
/// shared popover anchored to this item; right-click shows a small AppKit menu.
///
/// The owner (``MenuBarController``) must hold a strong reference — without it the
/// `NSStatusItem` is released and silently vanishes from the menu bar.
@MainActor
final class StatusItemController: NSObject {
    /// The pair id this item represents (used for diffing in MenuBarController).
    let pairID: Int

    private let pair: CurrencyPair
    private let store: RatesStore
    private let settings: AppSettings
    private let popoverController: PopoverController
    private let onOpenSettings: () -> Void

    private let statusItem: NSStatusItem
    private let hostingView: NSHostingView<StatusItemLabelView>

    init(
        pair: CurrencyPair,
        store: RatesStore,
        settings: AppSettings,
        popoverController: PopoverController,
        onOpenSettings: @escaping () -> Void
    ) {
        self.pairID = pair.id
        self.pair = pair
        self.store = store
        self.settings = settings
        self.popoverController = popoverController
        self.onOpenSettings = onOpenSettings

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.hostingView = NSHostingView(
            rootView: StatusItemLabelView(pair: pair, store: store, settings: settings)
        )

        super.init()

        configureButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            showContextMenu()
        } else {
            popoverController.toggle(relativeTo: sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Copera Currency",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        // Pop the menu, then detach it so left-clicks resume normal action.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Remove this item from the menu bar. Call before dropping the strong ref.
    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
