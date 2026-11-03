import AppKit
import CurrencyKit
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    /// Global shortcut that opens the popover with the converter focused (unset by default).
    static let openConverter = Self("openConverter")
}

/// Owns the AppKit side: status items, the shared popover, the Settings window
/// coordinator, the global shortcut and the store's lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private lazy var statusItems = StatusItemManager(store: model.store)
    private lazy var popover = PopoverController(model: model)
    private let windows = WindowCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("launched \(Bundle.main.shortVersion, privacy: .public) (\(Bundle.main.buildNumber, privacy: .public))")
        installActions()
        windows.start()

        statusItems.onPrimaryClick = { [weak self] button in self?.popover.toggle(from: button) }
        statusItems.makeMenu = { [weak self] in self?.makeStatusMenu() ?? NSMenu() }
        statusItems.start()

        observeAppearance()
        KeyboardShortcuts.onKeyUp(for: .openConverter) { [weak self] in self?.toggleConverter() }

        Task { await model.store.start() }

        #if DEBUG
        DebugLaunchHooks.run(model: model)
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.store.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reopening the app from Finder/Launchpad/Spotlight while it runs brings Settings
    /// forward when it is open, and shows the popover otherwise: the only way in when the
    /// menu bar items are hidden (System Settings › Menu Bar). `hasVisibleWindows` can't
    /// be used: the status item and bridge windows always count as visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if windows.hasSettingsWindow {
            windows.showSettings()
        } else {
            showPopover()
        }
        return false
    }

    // MARK: - Wiring

    private func installActions() {
        model.actions = AppModel.Actions(
            showSettings: { [weak self] in self?.windows.showSettings() },
            showPopover: { [weak self] in self?.showPopover() },
            closePopover: { [weak self] in self?.popover.close() }
        )
    }

    private func showPopover(focusingAmount: Bool = false) {
        guard let button = statusItems.primaryButton else { return }
        popover.show(from: button, focusingAmount: focusingAmount)
    }

    private func toggleConverter() {
        if popover.isShown {
            popover.close()
        } else {
            showPopover(focusingAmount: true)
        }
    }

    /// Light/Dark/System applies to the popover and Settings, never to the status items.
    private func observeAppearance() {
        withObservationTracking {
            let appearance = model.effectiveAppearance.nsAppearance
            popover.setAppearance(appearance)
            windows.setAppearance(appearance)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAppearance() }
        }
    }

    // MARK: - Status item menu

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Refresh", key: "r", symbol: "arrow.clockwise") { [weak self] in self?.model.refresh() })
        menu.addItem(.separator())
        menu.addItem(item("Settings…", key: ",", symbol: "gearshape") { [weak self] in self?.model.openSettings() })
        if let version = model.updater.availableUpdateVersion {
            menu.addItem(item("Update to \(version)…", symbol: "arrow.down.circle.fill") { [weak self] in self?.model.checkForUpdates() })
        } else if model.updater.isAvailable {
            menu.addItem(item("Check for Updates…", symbol: "arrow.down.circle") { [weak self] in self?.model.checkForUpdates() })
        }
        menu.addItem(item("About Copera Currency", symbol: "info.circle") { [weak self] in self?.model.openSettings(.about) })
        menu.addItem(.separator())
        menu.addItem(item("Quit Copera Currency", key: "q", symbol: "power") { [weak self] in self?.model.quit() })
        return menu
    }

    private func item(_ title: String, key: String = "", symbol: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}

/// `NSMenuItem` that runs a closure.
@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}

extension Bundle {
    /// `CFBundleShortVersionString`, e.g. `1.0.0`.
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// `CFBundleVersion`.
    var buildNumber: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
