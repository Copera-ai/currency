import AppKit
import CurrencyKit
import Observation

/// Settings window tabs (deep-linkable).
enum SettingsTab: String, CaseIterable, Hashable, Sendable {
    case general
    case currencies
    case appearance
    case about
}

/// Which side of the converter a currency picker edits.
enum ConverterSide: Hashable, Sendable {
    case from
    case to
}

/// App-level state and actions shared by the menu bar, the popover and Settings.
///
/// Logic lives in ``CurrencyStore`` (CurrencyKit); this type only adds UI navigation
/// (popover, Settings tab) and routes actions to the AppKit controllers, which the
/// ``AppDelegate`` installs as ``Actions``.
@MainActor
@Observable
final class AppModel {
    /// Hooks into the AppKit layer, installed once at launch.
    struct Actions {
        var showSettings: @MainActor () -> Void = {}
        var showPopover: @MainActor () -> Void = {}
        var closePopover: @MainActor () -> Void = {}
    }

    let store: CurrencyStore
    let updater: Updater
    let history: HistoryCache

    /// Selected Settings tab; set before opening Settings to deep-link.
    var settingsTab: SettingsTab = .general
    /// Presents the Add Pair sheet in Settings › Currencies.
    var isAddingPair = false

    // Popover UI state (kept here so the debug launch hooks and the global shortcut can drive it).
    var isPopoverShown = false
    var expandedPairID: CurrencyPair.ID?
    var pickerSide: ConverterSide?
    /// Bumped to move keyboard focus to the converter amount.
    var amountFocusRequest = 0

    /// Debug-only override for screenshots (never persisted).
    var appearanceOverride: AppearancePreference?

    @ObservationIgnored var actions = Actions()

    init(store: CurrencyStore = CurrencyStore(), updater: Updater = Updater()) {
        self.store = store
        self.updater = updater
        history = HistoryCache(store: store)
    }

    /// The appearance windows should use (Settings/override), `nil` = system.
    var effectiveAppearance: AppearancePreference {
        appearanceOverride ?? store.settings.appearance
    }

    // MARK: - Actions

    func openSettings(_ tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        actions.closePopover()
        actions.showSettings()
    }

    func addPairFromAnywhere() {
        isAddingPair = true
        openSettings(.currencies)
    }

    func refresh() {
        store.requestRefresh(.manual)
    }

    func checkForUpdates() {
        actions.closePopover()
        NSApp.activate()
        updater.checkForUpdates()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Copies a pair's current rate as plain digits (ungrouped, full precision).
    func copyRate(of pair: CurrencyPair) {
        guard let text = store.formatter.plainString(from: store.quote(for: pair)?.price) else { return }
        copy(text)
    }

    /// Loads `pair` into the converter (1 base → quote unless an amount is already set).
    func useInConverter(_ pair: CurrencyPair) {
        store.converter.from = pair.base
        store.converter.to = pair.quote
        if store.converter.amount == 0 { store.converter.amount = 1 }
        amountFocusRequest += 1
    }

    func currency(_ code: String) -> Currency? {
        store.catalog.currency(for: code)
    }
}

/// Chart data for the popover, loaded lazily per pair and range and kept across
/// popover openings (CurrencyKit memoizes and coalesces the actual requests).
@MainActor
@Observable
final class HistoryCache {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    struct Key: Hashable {
        let pair: CurrencyPair
        let range: HistoryRange
    }

    private(set) var series: [Key: PairHistory] = [:]
    private(set) var phases: [Key: Phase] = [:]
    @ObservationIgnored private let store: CurrencyStore

    init(store: CurrencyStore) {
        self.store = store
    }

    func history(_ pair: CurrencyPair, _ range: HistoryRange) -> PairHistory? {
        series[Key(pair: pair, range: range)]
    }

    func phase(_ pair: CurrencyPair, _ range: HistoryRange) -> Phase? {
        phases[Key(pair: pair, range: range)]
    }

    /// Fetches (or refreshes) a series. Keeps showing the previous one while loading.
    func load(_ pair: CurrencyPair, _ range: HistoryRange) async {
        let key = Key(pair: pair, range: range)
        if phases[key] == .loading { return }
        phases[key] = .loading
        do {
            series[key] = try await store.history(for: pair, range: range)
            phases[key] = .loaded
        } catch {
            phases[key] = .failed(CurrencyKitError(error).localizedDescription)
        }
    }
}
