import AppKit
import SwiftUI

/// Boots the menu-bar app and owns the top-level AppKit objects.
///
/// On launch it runs as a menu-bar-only agent (`.accessory`), constructs the data
/// store + settings, wires the popover / status-item controllers / settings
/// window, kicks off the first refresh, and starts the auto-refresh loop.
///
/// Strong references to every controller are held here — without them the status
/// items (and their `NSStatusItem`s) would be released and vanish.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: RatesStore?
    private var settings: AppSettings?
    private var popoverController: PopoverController?
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: no Dock icon, no app-menu focus stealing.
        NSApp.setActivationPolicy(.accessory)

        // Data layer: real providers + standard-defaults persistence.
        let store = RatesStore(
            fiatProvider: FawazFiatProvider(),
            cryptoProvider: CoinbaseCryptoProvider(),
            persistence: PersistenceStore()
        )
        let settings = AppSettings()

        // Keep AppKit chrome (status-item labels, popover) in sync with the
        // user's appearance preference.
        AppearanceSync.apply(settings.appearance)

        // Shared popover + settings window. The popover opens Settings via a
        // forward-referenced controller (created just below) to break the cycle
        // between the two controllers. The optional tab deep-links a section
        // ("Manage" → Currencies); `nil` reopens the last-viewed tab.
        var openSettings: (SettingsTab?) -> Void = { _ in }
        let popoverController = PopoverController(
            store: store,
            settings: settings,
            onOpenSettings: { tab in openSettings(tab) }
        )
        let settingsWindowController = SettingsWindowController(
            store: store,
            settings: settings,
            popoverController: popoverController
        )
        openSettings = { tab in
            if let tab { settingsWindowController.show(tab: tab) }
            else { settingsWindowController.show() }
        }

        // Menu-bar items, driven by the store's tracked pairs.
        let menuBarController = MenuBarController(
            store: store,
            settings: settings,
            popoverController: popoverController,
            onOpenSettings: { settingsWindowController.show() }
        )

        self.store = store
        self.settings = settings
        self.popoverController = popoverController
        self.settingsWindowController = settingsWindowController
        self.menuBarController = menuBarController

        menuBarController.start()

        // First refresh, then begin the auto-refresh loop.
        Task {
            await store.refresh()
            #if DEBUG
            print("[CoperaCurrency] first refresh complete — rates: \(store.rates.count), state: \(store.loadState)")
            fflush(stdout) // ensure the line reaches a non-TTY pipe during smoke tests
            #endif
            store.startTimer()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }
}
