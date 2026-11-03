import Foundation
import Observation

/// The observable source of truth the UI binds to: pairs, live quotes, converter,
/// settings, load state and history.
///
/// Create one with ``init()`` (live dependencies), call ``start()`` once at launch
/// and ``stop()`` on termination. Every mutation is persisted immediately, except
/// converter edits (saved at most every ``Dependencies/converterSaveDelay``; ``stop()``
/// flushes them).
@MainActor
@Observable
public final class CurrencyStore {
    // MARK: - Dependencies

    /// Everything the store talks to. Use ``live()`` in the app and inject fakes in tests.
    public struct Dependencies: Sendable {
        public var stateStore: StateStore
        public var engine: RatesEngine
        public var history: HistoryService
        public var catalog: CurrencyCatalog
        public var locale: Locale
        public var now: @Sendable () -> Date
        /// Converter edits (one per keystroke) are coalesced into one save after this delay.
        public var converterSaveDelay: Duration

        public init(
            http: any HTTPClient,
            stateStore: StateStore,
            cache: DiskCache,
            catalog: CurrencyCatalog = .shared,
            engineConfiguration: RatesEngine.Configuration = RatesEngine.Configuration(),
            locale: Locale = .autoupdatingCurrent,
            now: @escaping @Sendable () -> Date = { Date() },
            converterSaveDelay: Duration = .milliseconds(500)
        ) {
            self.stateStore = stateStore
            engine = RatesEngine(http: http, cache: cache, catalog: catalog, configuration: engineConfiguration, now: now)
            history = HistoryService(http: http, cache: cache, catalog: catalog, now: now)
            self.catalog = catalog
            self.locale = locale
            self.now = now
            self.converterSaveDelay = converterSaveDelay
        }

        /// Real network, Application Support state and Caches directory.
        public static func live() -> Dependencies {
            Dependencies(http: URLSessionHTTPClient(), stateStore: .standard(), cache: .standard())
        }
    }

    /// Result of ``addPair(base:quote:showInMenuBar:)``.
    public enum AddPairResult: Equatable, Sendable {
        case added
        case duplicate
        case sameCurrency
        case unknownCurrency(String)
    }

    // MARK: - Observable state

    public let catalog: CurrencyCatalog
    /// Tracked pairs in display order.
    public private(set) var pairs: [TrackedPair]
    /// User preferences. Changing ``UserSettings/refreshInterval`` reschedules immediately.
    public var settings: UserSettings {
        didSet { settingsDidChange(from: oldValue) }
    }
    /// Converter inputs.
    public var converter: ConverterState {
        didSet { if converter != oldValue { schedulePersist() } }
    }
    /// The latest merged rates, or `nil` before anything loaded.
    public private(set) var snapshot: RatesSnapshot?
    public private(set) var loadState: LoadState = .idle
    /// When rates were last fetched successfully.
    public private(set) var lastUpdated: Date?
    /// A refresh is in flight (shown as a spinner over existing data).
    public private(set) var isRefreshing = false
    /// The most recent refresh problem, cleared on full success.
    public private(set) var lastError: CurrencyKitError?
    /// Connectivity as last reported by the system (`nil` = unknown yet).
    public private(set) var isOnline: Bool?
    /// How the persisted state was obtained at launch (e.g. to tell the user a corrupt
    /// settings file was backed up).
    public let persistenceOutcome: StateStore.LoadOutcome
    /// Formatter matching the user's locale and ``UserSettings/decimals``.
    public private(set) var formatter: RateFormatter
    /// Parser for converter input in the user's locale.
    public let amountParser: AmountParser

    // MARK: - Private

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var scheduler: RefreshScheduler?
    @ObservationIgnored private let wakeObserver = WakeObserver()
    @ObservationIgnored private let networkMonitor = NetworkMonitor()
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// A store with live dependencies.
    public convenience init() {
        self.init(dependencies: .live())
    }

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
        catalog = dependencies.catalog
        let (state, outcome) = dependencies.stateStore.load()
        pairs = state.pairs
        settings = state.settings
        converter = state.converter
        persistenceOutcome = outcome
        formatter = RateFormatter(locale: dependencies.locale, decimals: state.settings.decimals)
        amountParser = AmountParser(locale: dependencies.locale)
    }

    // MARK: - Lifecycle

    /// Shows cached rates, then starts automatic refreshing (timer, wake, network restored).
    public func start() async {
        guard scheduler == nil else { return }
        if snapshot == nil, let cached = await dependencies.engine.restoreFromDisk() {
            snapshot = cached
            lastUpdated = cached.fetchedAt
            loadState = .stale
        }

        let scheduler = RefreshScheduler(interval: settings.refreshInterval.duration) { [weak self] triggers in
            await self?.performRefresh(force: triggers.contains { $0.forcesRefresh })
        }
        self.scheduler = scheduler
        wakeObserver.onWake = { [weak scheduler] in scheduler?.trigger(.wake) }
        networkMonitor.onChange = { [weak self] online in self?.isOnline = online }
        networkMonitor.onRestored = { [weak scheduler] in scheduler?.trigger(.networkRestored) }
        wakeObserver.start()
        networkMonitor.start()
        scheduler.start()
    }

    /// Stops automatic refreshing and system observers, and writes pending changes.
    public func stop() {
        flushPendingSave()
        scheduler?.stop()
        scheduler = nil
        wakeObserver.stop()
        networkMonitor.stop()
    }

    /// Refreshes now, ignoring TTLs and backoff. Returns when done.
    public func refresh() async {
        await performRefresh(force: true)
    }

    /// Asks the scheduler for a refresh (debounced and coalesced with other triggers).
    public func requestRefresh(_ trigger: RefreshTrigger = .manual) {
        if let scheduler {
            scheduler.trigger(trigger)
        } else {
            Task { await performRefresh(force: trigger.forcesRefresh) }
        }
    }

    func performRefresh(force: Bool) async {
        isRefreshing = true
        if snapshot == nil { loadState = .loading }
        defer { isRefreshing = false }
        do {
            apply(try await dependencies.engine.refresh(force: force))
        } catch {
            let failure = CurrencyKitError(error)
            lastError = failure
            if failure.isConnectivity || isOnline == false {
                loadState = .offline
            } else {
                loadState = snapshot == nil ? .error(failure) : .stale
            }
            Log.store.error("Refresh failed: \(failure.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ fresh: RatesSnapshot) {
        snapshot = fresh
        lastUpdated = fresh.fetchedAt
        lastError = fresh.issues.values.first
        if fresh.issues.isEmpty {
            loadState = .loaded
        } else if fresh.issues.values.allSatisfy(\.isConnectivity) || isOnline == false {
            loadState = .offline
        } else {
            loadState = .stale
        }
    }

    // MARK: - Quotes

    /// Live quote for `pair`, or `nil` until rates for both sides are known.
    public func quote(for pair: CurrencyPair) -> PairQuote? {
        snapshot?.quote(for: pair)
    }

    /// Quotes for every tracked pair, keyed by pair id.
    public var quotes: [CurrencyPair.ID: PairQuote] {
        var result: [CurrencyPair.ID: PairQuote] = [:]
        for tracked in pairs {
            if let quote = quote(for: tracked.pair) { result[tracked.id] = quote }
        }
        return result
    }

    /// `"Updated just now"`, `"Updated 5 minutes ago"`, or `"Not updated yet"`.
    /// For a self-updating label, SwiftUI's `Text(lastUpdated, style: .relative)` also works.
    public func updatedText(relativeTo now: Date = Date()) -> String {
        Self.updatedText(lastUpdated: lastUpdated, now: now, locale: dependencies.locale)
    }

    nonisolated public static func updatedText(lastUpdated: Date?, now: Date, locale: Locale) -> String {
        guard let lastUpdated else { return "Not updated yet" }
        if now.timeIntervalSince(lastUpdated) < 45 { return "Updated just now" }
        // RelativeDateTimeFormatter (unlike Date.RelativeFormatStyle) takes an explicit
        // reference date. It is cheap to create and this runs at most once per tick.
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.formattingContext = .middleOfSentence
        return "Updated \(formatter.localizedString(for: lastUpdated, relativeTo: now))"
    }

    // MARK: - Pairs

    /// Pairs shown in the menu bar, in display order.
    public var menuBarPairs: [TrackedPair] { pairs.filter(\.showInMenuBar) }

    /// Starred pairs, in display order.
    public var favoritePairs: [TrackedPair] { pairs.filter(\.isFavorite) }

    /// Appends a pair. Codes must exist in the catalog and differ; duplicates are rejected.
    @discardableResult
    public func addPair(base: String, quote: String, showInMenuBar: Bool = false) -> AddPairResult {
        let pair = CurrencyPair(base: base, quote: quote)
        guard pair.base != pair.quote else { return .sameCurrency }
        for code in [pair.base, pair.quote] where !catalog.contains(code) {
            return .unknownCurrency(code)
        }
        guard !pairs.contains(where: { $0.pair == pair }) else { return .duplicate }
        pairs.append(TrackedPair(pair, showInMenuBar: showInMenuBar))
        persist()
        return .added
    }

    public func removePair(_ id: CurrencyPair.ID) {
        pairs.removeAll { $0.id == id }
        persist()
    }

    public func removePairs(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where pairs.indices.contains(index) {
            pairs.remove(at: index)
        }
        persist()
    }

    /// Reorders the list (SwiftUI `onMove` semantics). This changes the actual array
    /// order, so the new order sticks.
    public func movePairs(fromOffsets source: IndexSet, toOffset destination: Int) {
        pairs.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Reorders the menu-bar subset (`onMove` offsets into ``menuBarPairs``). Pairs not
    /// shown in the menu bar keep their positions.
    public func moveMenuBarPairs(fromOffsets source: IndexSet, toOffset destination: Int) {
        let slots = pairs.indices.filter { pairs[$0].showInMenuBar }
        var subset = slots.map { pairs[$0] }
        subset.move(fromOffsets: source, toOffset: destination)
        for (slot, item) in zip(slots, subset) { pairs[slot] = item }
        persist()
    }

    public func toggleFavorite(_ id: CurrencyPair.ID) {
        update(id) { $0.isFavorite.toggle() }
    }

    public func setFavorite(_ id: CurrencyPair.ID, _ isFavorite: Bool) {
        update(id) { $0.isFavorite = isFavorite }
    }

    public func setShowInMenuBar(_ id: CurrencyPair.ID, _ show: Bool) {
        update(id) { $0.showInMenuBar = show }
    }

    public func toggleShowInMenuBar(_ id: CurrencyPair.ID) {
        update(id) { $0.showInMenuBar.toggle() }
    }

    private func update(_ id: CurrencyPair.ID, _ change: (inout TrackedPair) -> Void) {
        guard let index = pairs.firstIndex(where: { $0.id == id }) else { return }
        change(&pairs[index])
        persist()
    }

    // MARK: - Menu bar

    /// What a menu-bar item shows for `pair` under the current settings.
    public func menuBarLabel(for pair: CurrencyPair) -> MenuBarLabel {
        let quote = quote(for: pair)
        let prefix: String = switch settings.menuBarLabelFormat {
        case .pair: pair.id
        case .symbol: catalog.currency(for: pair.quote)?.symbol ?? pair.quote
        case .value: ""
        case .flag: catalog.currency(for: pair.base)?.badge ?? pair.base
        }
        return MenuBarLabel(
            prefix: prefix,
            value: formatter.string(from: quote?.price),
            trend: quote?.trend ?? .flat,
            showsArrow: settings.showChangeArrow
        )
    }

    // MARK: - Converter

    /// ``converter``'s amount converted, or `nil` while rates are missing.
    public var converterResult: Double? {
        convert(converter.amount, from: converter.from, to: converter.to)
    }

    /// Converts `amount` between any two catalog currencies.
    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        snapshot?.convert(amount, from: from, to: to)
    }

    /// Swaps the converter's currencies.
    public func swapConverterCurrencies() {
        converter = converter.swapped
    }

    /// Parses `text` with ``amountParser`` and stores it as the converter amount; blank
    /// text means 0. Returns `false` (leaving the amount unchanged) when `text` is not a
    /// valid amount.
    @discardableResult
    public func setConverterAmount(text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : amountParser.parse(text)
        guard let value else { return false }
        converter.amount = value
        return true
    }

    // MARK: - History

    /// Price series for `pair`. See ``HistoryService/history(for:range:)``.
    public func history(for pair: CurrencyPair, range: HistoryRange) async throws -> PairHistory {
        try await dependencies.history.history(for: pair, range: range)
    }

    public func availableRanges(for pair: CurrencyPair) -> [HistoryRange] {
        catalog.availableRanges(for: pair)
    }

    public func defaultRange(for pair: CurrencyPair) -> HistoryRange {
        catalog.defaultRange(for: pair)
    }

    // MARK: - Persistence

    private func settingsDidChange(from old: UserSettings) {
        guard settings != old else { return }
        if settings.decimals != old.decimals {
            formatter = RateFormatter(locale: dependencies.locale, decimals: settings.decimals)
        }
        if settings.refreshInterval != old.refreshInterval {
            scheduler?.setInterval(settings.refreshInterval.duration)
        }
        persist()
    }

    /// Writes any converter change still waiting for its coalesced save.
    public func flushPendingSave() {
        if pendingSave != nil { persist() }
    }

    private func schedulePersist() {
        pendingSave?.cancel()
        let delay = dependencies.converterSaveDelay
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try dependencies.stateStore.save(PersistedState(pairs: pairs, settings: settings, converter: converter))
        } catch {
            Log.persistence.error("Saving state failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The pieces of a menu-bar item.
public struct MenuBarLabel: Hashable, Sendable {
    /// Text before the value (may be empty).
    public let prefix: String
    /// Formatted price.
    public let value: String
    public let trend: Trend
    /// Whether the user wants the trend arrow shown.
    public let showsArrow: Bool

    /// Plain-text rendering, e.g. `"USD/BRL 5.44 ▲"`.
    public var text: String {
        var parts = [prefix, value].filter { !$0.isEmpty }
        if showsArrow, let arrow = trend.arrow { parts.append(arrow) }
        return parts.joined(separator: " ")
    }
}

extension Array {
    /// Moves the elements at `source` to `destination` (SwiftUI `onMove` semantics).
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { indices.contains($0) }
        let moving = valid.map { self[$0] }
        let insertion = destination - valid.filter { $0 < destination }.count
        for index in valid.sorted(by: >) { remove(at: index) }
        insert(contentsOf: moving, at: Swift.max(0, Swift.min(insertion, count)))
    }
}
