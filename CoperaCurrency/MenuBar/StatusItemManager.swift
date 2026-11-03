import AppKit
import CurrencyKit
import Observation

/// One `NSStatusItem` per pair shown in the menu bar, kept in sync with
/// ``CurrencyStore/menuBarPairs`` by diffing: rate ticks only retitle existing items
/// (no flicker); removals remove items; a new order (or a pair added anywhere but the
/// left end) rebuilds the items so they match the Settings order.
///
/// Each item has `autosaveName = "pair.<id>"`, so positions the user sets with ⌘-drag
/// survive relaunches, until the order changes in Settings. When no pair is in the
/// menu bar a single template glyph keeps the app reachable.
///
/// Labels never get a forced appearance: they inherit the menu bar's own (vibrant)
/// appearance, so they stay readable on any wallpaper.
@MainActor
final class StatusItemManager: NSObject {
    /// Left click on an item (toggle the popover anchored to it).
    var onPrimaryClick: (NSStatusBarButton) -> Void = { _ in }
    /// The right-click menu.
    var makeMenu: () -> NSMenu = { NSMenu() }

    private let store: CurrencyStore
    private var items: [CurrencyPair.ID: NSStatusItem] = [:]
    /// Ids of `items`, left to right as created.
    private var order: [CurrencyPair.ID] = []
    private var didInitialSync = false
    private var markItem: NSStatusItem?
    private var labelCache: [CurrencyPair.ID: MenuBarLabel] = [:]

    init(store: CurrencyStore) {
        self.store = store
    }

    func start() {
        observe()
    }

    /// The button popovers should anchor to: the first pair item actually on screen
    /// (the menu bar hides items that don't fit), else the glyph or any item.
    var primaryButton: NSStatusBarButton? {
        for tracked in store.menuBarPairs {
            if let button = items[tracked.id]?.button, Self.isOnScreen(button) { return button }
        }
        return markItem?.button ?? store.menuBarPairs.lazy.compactMap { self.items[$0.id]?.button }.first
    }

    private static func isOnScreen(_ button: NSStatusBarButton) -> Bool {
        guard let frame = button.window?.frame else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    // MARK: - Sync

    private func observe() {
        withObservationTracking {
            sync()
        } onChange: { [weak self] in
            // Fires once per change, before the new value is set: re-read on the next turn.
            Task { @MainActor in self?.observe() }
        }
    }

    private func sync() {
        let pairs = store.menuBarPairs
        let wanted = pairs.map(\.id)
        let wantedSet = Set(wanted)

        for id in order where !wantedSet.contains(id) {
            removeItem(id)
        }
        order.removeAll { !wantedSet.contains($0) }

        if order != wanted {
            // macOS inserts new items to the left of existing ones, so new pairs at the
            // left end can just be created; any other change rebuilds every item.
            let isLeftAdd = wanted.suffix(order.count).elementsEqual(order)
            if !isLeftAdd {
                for id in order { removeItem(id) }
                order = []
                Log.menuBar.debug("rebuilding items in order \(wanted.joined(separator: " "), privacy: .public)")
            }
            // At launch keep the positions saved by ⌘-drag; afterwards a saved position
            // would put the item back where it was instead of in the Settings order.
            let created = wanted.prefix(wanted.count - order.count)
            if didInitialSync {
                for id in created { UserDefaults.standard.removeObject(forKey: Self.positionKey(id)) }
            }
            // Create right to left so they end up in display order.
            for id in created.reversed() {
                items[id] = makeItem(autosaveName: Self.autosaveName(id), id: id)
                Log.menuBar.debug("added item \(id, privacy: .public)")
            }
            order = wanted
        }
        didInitialSync = true

        for tracked in pairs {
            guard let button = items[tracked.id]?.button else { continue }
            let label = store.menuBarLabel(for: tracked.pair)
            guard labelCache[tracked.id] != label else { continue }
            labelCache[tracked.id] = label
            apply(label, pair: tracked.pair, to: button)
        }

        if pairs.isEmpty {
            if markItem == nil { markItem = makeMarkItem() }
        } else if let markItem {
            NSStatusBar.system.removeStatusItem(markItem)
            self.markItem = nil
        }
    }

    private func removeItem(_ id: CurrencyPair.ID) {
        if let item = items.removeValue(forKey: id) {
            NSStatusBar.system.removeStatusItem(item)
        }
        labelCache[id] = nil
        Log.menuBar.debug("removed item \(id, privacy: .public)")
    }

    private static func autosaveName(_ id: CurrencyPair.ID) -> String {
        "pair.\(id)"
    }

    /// Where AppKit saves an autosaved item's menu bar position.
    private static func positionKey(_ id: CurrencyPair.ID) -> String {
        "NSStatusItem Preferred Position \(autosaveName(id))"
    }

    private func makeItem(autosaveName: String, id: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        item.isVisible = true
        if let button = item.button {
            button.identifier = NSUserInterfaceItemIdentifier(id)
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        return item
    }

    private func makeMarkItem() -> NSStatusItem {
        let item = makeItem(autosaveName: "mark", id: "mark")
        if let button = item.button {
            let image = NSImage(named: "CurrencyMark")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Copera Currency")
            button.toolTip = "Copera Currency"
        }
        return item
    }

    // MARK: - Labels

    private func apply(_ label: MenuBarLabel, pair: CurrencyPair, to button: NSStatusBarButton) {
        button.attributedTitle = Self.attributedTitle(for: label)
        button.imagePosition = .noImage
        let spoken = Self.accessibilityText(for: label, pair: pair, quote: store.quote(for: pair), formatter: store.formatter)
        button.setAccessibilityLabel(spoken)
        button.toolTip = spoken
    }

    /// Prefix in the menu bar font, digits monospaced, and a small colored arrow.
    static func attributedTitle(for label: MenuBarLabel) -> NSAttributedString {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let result = NSMutableAttributedString()
        if !label.prefix.isEmpty {
            result.append(NSAttributedString(
                string: label.prefix + " ",
                attributes: [.font: NSFont.systemFont(ofSize: size, weight: .regular)]
            ))
        }
        result.append(NSAttributedString(
            string: label.value,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)]
        ))
        if label.showsArrow, let arrow = label.trend.arrow {
            result.append(NSAttributedString(
                string: " " + arrow,
                attributes: [
                    .font: NSFont.systemFont(ofSize: size * 0.6, weight: .bold),
                    .foregroundColor: label.trend.nsColor,
                    .baselineOffset: size * 0.14,
                ]
            ))
        }
        return result
    }

    static func accessibilityText(for label: MenuBarLabel, pair: CurrencyPair, quote: PairQuote?, formatter: RateFormatter) -> String {
        var text = "\(pair.base) to \(pair.quote): \(label.value)"
        if let quote, quote.change24h != nil {
            text += ", " + ChangePill.spoken(quote.change24h, formatter: formatter).lowercased()
        }
        return text
    }

    // MARK: - Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            showMenu(for: sender)
        } else {
            onPrimaryClick(sender)
        }
    }

    private func showMenu(for button: NSStatusBarButton) {
        guard let item = (items.values.first { $0.button === button }) ?? (markItem?.button === button ? markItem : nil) else { return }
        // Attach the menu only for this click so left clicks keep toggling the popover.
        item.menu = makeMenu()
        button.performClick(nil)
        item.menu = nil
    }
}
