import Foundation
import Observation

/// How often the rates auto-refresh loop runs.
enum RefreshInterval: Int, CaseIterable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600
    case threeHours = 10800

    /// The interval in seconds (alias for `rawValue`).
    var seconds: Int { rawValue }
}

/// The central, observable source of truth for currencies, pairs and rates.
///
/// All mutable state lives on the main actor (the UI observes it). Pure math —
/// formatting, rate/convert/change computation and the 24h-baseline diff — is
/// exposed as `nonisolated static` functions so tests can call them
/// synchronously off the main actor; instance methods are thin wrappers over
/// these.
@MainActor
@Observable
final class RatesStore {
    // MARK: - Observable state

    /// Current normalized rates, keyed by uppercase code.
    var rates: [String: NormalizedRate] = [:]
    /// User-tracked pairs (all of them, tracked and untracked).
    var pairs: [CurrencyPair]
    /// When `rates` was last successfully updated.
    var lastUpdated: Date?
    /// The fiat provider's reported date string, if known.
    var fiatDate: String?
    /// The current load lifecycle state.
    var loadState: LoadState = .idle
    /// The auto-refresh cadence; persisted to `UserDefaults`.
    var refreshInterval: RefreshInterval {
        didSet { persistence.saveRefreshIntervalRaw(refreshInterval.rawValue) }
    }

    // MARK: - Dependencies

    private let fiatProvider: RatesProvider
    private let cryptoProvider: RatesProvider
    private let persistence: PersistenceStore

    /// Handle to the running refresh loop, if any.
    private var refreshTask: Task<Void, Never>?

    // MARK: - Init

    init(
        fiatProvider: RatesProvider,
        cryptoProvider: RatesProvider,
        persistence: PersistenceStore
    ) {
        self.fiatProvider = fiatProvider
        self.cryptoProvider = cryptoProvider
        self.persistence = persistence

        // Restore the refresh interval before any didStore side effects matter.
        if let raw = persistence.loadRefreshIntervalRaw(),
           let interval = RefreshInterval(rawValue: raw) {
            self.refreshInterval = interval
        } else {
            self.refreshInterval = .fiveMinutes
        }

        // Seed pairs on first launch.
        self.pairs = persistence.loadPairs()

        // Restore last-good rates so the UI has something to show immediately.
        if let snapshot = persistence.loadLastGood() {
            self.rates = snapshot.rates
            self.lastUpdated = snapshot.updatedAt
            self.fiatDate = snapshot.fiatDate
        }
    }

    // Note: no `deinit` cancel of `refreshTask`. `deinit` is nonisolated and
    // cannot touch main-actor state under Swift 6. The refresh loop captures
    // `[weak self]` and returns as soon as `self` is `nil`, so it self-
    // terminates; callers should still invoke `stop()` for prompt cancellation.

    // MARK: - Refresh

    /// Fetch fresh rates from both providers concurrently and merge them.
    ///
    /// The fiat provider is gated to at most hourly (Fawaz updates daily); if a
    /// fiat fetch happened within the last hour, existing fiat rates are reused.
    /// Crypto values win over fiat on key collisions; `USD` is forced to `1`.
    /// On partial failure, previously-good data for the failing half is kept and
    /// `loadState` becomes `.stale`. On total failure with no data, `loadState`
    /// becomes `.offline`.
    func refresh() async {
        loadState = .loading

        let requestedCodes = Set(Currency.supported.map(\.code))
        let now = Date()

        // Gate the fiat fetch to hourly.
        let lastFiat = persistence.loadLastFiatFetch()
        let shouldFetchFiat = lastFiat.map { now.timeIntervalSince($0) >= 3600 } ?? true

        // Kick off concurrent fetches.
        async let fiatResult: [String: Double]? = shouldFetchFiat
            ? Self.tryFetch(fiatProvider, codes: requestedCodes)
            : nil
        async let cryptoResult: [String: Double]? = Self.tryFetch(cryptoProvider, codes: requestedCodes)

        let fiatMap = await fiatResult
        let cryptoMap = await cryptoResult

        let fiatFetchSucceeded = fiatMap != nil
        let cryptoFetchSucceeded = cryptoMap != nil

        // Existing usd-per-unit values, used to backfill the half we didn't or
        // couldn't refresh.
        let existing = rates.mapValues(\.usdPerUnit)

        // Determine the fiat half of the merged map.
        let fiatPart: [String: Double]
        if let fiatMap {
            fiatPart = fiatMap
        } else {
            // Reuse existing fiat values (non-crypto codes from prior data).
            let cryptoCodes = Set(Currency.supported.filter { $0.kind == .crypto }.map(\.code))
            fiatPart = existing.filter { !cryptoCodes.contains($0.key) }
        }

        // Determine the crypto half.
        let cryptoPart: [String: Double]
        if let cryptoMap {
            cryptoPart = cryptoMap
        } else {
            let cryptoCodes = Set(Currency.supported.filter { $0.kind == .crypto }.map(\.code))
            cryptoPart = existing.filter { cryptoCodes.contains($0.key) }
        }

        // Merge: fiat first, then crypto overwrites on collisions.
        var merged = fiatPart
        for (code, value) in cryptoPart {
            merged[code] = value
        }

        // Total failure detection: if neither provider produced anything and we
        // have no usable prior data (beyond a synthetic USD anchor), surface
        // offline rather than persisting a USD-only snapshot. We evaluate this
        // BEFORE injecting the USD anchor so the anchor can't mask emptiness.
        let hasRealData = !merged.filter { $0.key != "USD" }.isEmpty
        if !hasRealData {
            loadState = rates.isEmpty ? .offline : .stale(since: lastUpdated)
            return
        }

        // USD is the normalization anchor: always 1 USD per USD.
        merged["USD"] = 1

        // Resolve the fiat date (new fetch may not expose it through the
        // protocol; fall back to the previous value).
        let resolvedFiatDate = fiatDate

        // Roll the daily baseline forward if needed, then compute 24h changes.
        let baseline = Self.resolvedBaseline(
            now: merged,
            stored: persistence.loadDailyBaseline(),
            newFiatDate: resolvedFiatDate,
            at: now
        )
        if baseline.didRoll {
            persistence.saveDailyBaseline(baseline.snapshot)
        }
        let changes = Self.computeChange24h(now: merged, baseline: baseline.snapshot)

        // Build the new rates map.
        var newRates: [String: NormalizedRate] = [:]
        for (code, usd) in merged {
            newRates[code] = NormalizedRate(usdPerUnit: usd, change24h: changes[code] ?? 0)
        }

        rates = newRates
        lastUpdated = now
        fiatDate = resolvedFiatDate

        // Persist last-good.
        persistence.saveLastGood(RatesSnapshot(rates: newRates, updatedAt: now, fiatDate: resolvedFiatDate))

        // Record the fiat fetch time only if it actually succeeded.
        if fiatFetchSucceeded {
            persistence.saveLastFiatFetch(now)
        }

        // A provider failure while we kept data → stale; otherwise loaded.
        let anyFailure = (shouldFetchFiat && !fiatFetchSucceeded) || !cryptoFetchSucceeded
        loadState = anyFailure ? .stale(since: now) : .loaded
    }

    /// Run a provider fetch, swallowing errors into `nil`.
    private nonisolated static func tryFetch(_ provider: RatesProvider, codes: Set<String>) async -> [String: Double]? {
        do {
            return try await provider.fetchUSDPerUnit(for: codes)
        } catch {
            return nil
        }
    }

    // MARK: - 24h baseline diff (pure)

    /// Per-code 24h change percentage relative to a daily baseline.
    ///
    /// Returns `(now/baseline - 1) * 100` for codes present in both; `0` when no
    /// baseline value exists for a code (cold start).
    nonisolated static func computeChange24h(now: [String: Double], baseline: RatesSnapshot?) -> [String: Double] {
        var result: [String: Double] = [:]
        for (code, value) in now {
            if let base = baseline?.rates[code]?.usdPerUnit, base != 0 {
                result[code] = (value / base - 1) * 100
            } else {
                result[code] = 0
            }
        }
        return result
    }

    /// Decide whether the daily baseline should roll forward and produce the
    /// baseline snapshot to diff against.
    ///
    /// Rolls when the stored baseline is missing, older than ~24h, or the fiat
    /// date changed. When rolling, the returned snapshot is the *current* data
    /// (and `didRoll` is `true`, signalling the caller to persist it).
    nonisolated static func resolvedBaseline(
        now: [String: Double],
        stored: RatesSnapshot?,
        newFiatDate: String?,
        at date: Date
    ) -> (snapshot: RatesSnapshot, didRoll: Bool) {
        let currentSnapshot = RatesSnapshot(
            rates: now.mapValues { NormalizedRate(usdPerUnit: $0, change24h: 0) },
            updatedAt: date,
            fiatDate: newFiatDate
        )

        guard let stored else {
            return (currentSnapshot, true)
        }

        let ageExceeded = date.timeIntervalSince(stored.updatedAt) >= 86400
        let fiatDateChanged: Bool = {
            guard let newFiatDate, let oldFiatDate = stored.fiatDate else { return false }
            return newFiatDate != oldFiatDate
        }()

        if ageExceeded || fiatDateChanged {
            return (currentSnapshot, true)
        }
        return (stored, false)
    }

    // MARK: - Pure math helpers (nonisolated static)

    /// `usdPerUnit[base] / usdPerUnit[quote]`, or `.nan` if either is missing.
    nonisolated static func rate(_ base: String, _ quote: String, in map: [String: Double]) -> Double {
        guard let b = map[base], let q = map[quote], q != 0 else { return .nan }
        return b / q
    }

    /// `amount * usdPerUnit[from] / usdPerUnit[to]`.
    nonisolated static func convert(amount: Double, from: String, to: String, in map: [String: Double]) -> Double {
        guard let f = map[from], let t = map[to], t != 0 else { return .nan }
        return amount * f / t
    }

    /// `change24h[base] - change24h[quote]`.
    nonisolated static func change(_ base: String, _ quote: String, in changes: [String: Double]) -> Double {
        (changes[base] ?? 0) - (changes[quote] ?? 0)
    }

    /// Format a value exactly like the prototype's `fmt()`.
    ///
    /// Non-finite → `"—"`. Decimals chosen by magnitude bucket, en_US grouping.
    nonisolated static func fmt(_ v: Double) -> String {
        guard v.isFinite else { return "—" }
        let d: Int
        if v >= 1000 {
            d = 2
        } else if v >= 1 {
            d = 2
        } else if v >= 0.01 {
            d = 4
        } else {
            d = 6
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = d
        formatter.maximumFractionDigits = d
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: v)) ?? "—"
    }

    // MARK: - Pure math helpers (instance wrappers)

    /// USD-per-unit map derived from current `rates`.
    private var usdPerUnitMap: [String: Double] {
        rates.mapValues(\.usdPerUnit)
    }

    /// 24h-change map derived from current `rates`.
    private var changeMap: [String: Double] {
        rates.mapValues(\.change24h)
    }

    func rate(_ pair: CurrencyPair) -> Double {
        Self.rate(pair.base, pair.quote, in: usdPerUnitMap)
    }

    func rate(_ base: String, _ quote: String) -> Double {
        Self.rate(base, quote, in: usdPerUnitMap)
    }

    func convert(amount: Double, from: String, to: String) -> Double {
        Self.convert(amount: amount, from: from, to: to, in: usdPerUnitMap)
    }

    func change(_ pair: CurrencyPair) -> Double {
        Self.change(pair.base, pair.quote, in: changeMap)
    }

    func fmt(_ v: Double) -> String {
        Self.fmt(v)
    }

    /// A human-friendly "Updated …" label based on `lastUpdated`.
    func relativeUpdatedLabel() -> String {
        guard let lastUpdated else { return "Never" }
        let seconds = Int(Date().timeIntervalSince(lastUpdated))
        if seconds < 0 { return "Updated just now" }
        if seconds < 60 { return "Updated \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Updated \(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "Updated \(hours)h ago" }
        let days = hours / 24
        return "Updated \(days)d ago"
    }

    // MARK: - Tracked list

    /// Tracked pairs, favourites first, then by `sortOrder`.
    var trackedSorted: [CurrencyPair] {
        pairs
            .filter(\.isTracked)
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    // MARK: - Mutations

    func toggleFavorite(_ id: Int) {
        guard let index = pairs.firstIndex(where: { $0.id == id }) else { return }
        pairs[index].isFavorite.toggle()
        persistence.savePairs(pairs)
    }

    func toggleTracked(_ id: Int) {
        guard let index = pairs.firstIndex(where: { $0.id == id }) else { return }
        pairs[index].isTracked.toggle()
        persistence.savePairs(pairs)
    }

    /// Add a new tracked pair. Rejects `base == quote` and exact duplicates.
    /// Returns `true` on success.
    @discardableResult
    func addPair(base: String, quote: String) -> Bool {
        let b = base.uppercased()
        let q = quote.uppercased()
        guard b != q else { return false }
        guard !pairs.contains(where: { $0.base == b && $0.quote == q }) else { return false }

        let newId = (pairs.map(\.id).max() ?? 0) + 1
        let newSortOrder = (pairs.map(\.sortOrder).max() ?? 0) + 1
        pairs.append(
            CurrencyPair(id: newId, base: b, quote: q, isFavorite: false, isTracked: true, sortOrder: newSortOrder)
        )
        persistence.savePairs(pairs)
        return true
    }

    func removePair(_ id: Int) {
        pairs.removeAll { $0.id == id }
        persistence.savePairs(pairs)
    }

    /// Reorder the tracked pairs to match `orderedIds`, rewriting `sortOrder`.
    ///
    /// IDs not present in `orderedIds` keep their relative order after the
    /// reordered ones. Untracked pairs are left untouched (still persisted).
    func reorder(_ orderedIds: [Int]) {
        var order: [Int: Int] = [:]
        for (index, id) in orderedIds.enumerated() {
            order[id] = index
        }
        // Assign sortOrder by the requested order; unspecified ids go after.
        let fallbackBase = (order.values.max() ?? -1) + 1
        for index in pairs.indices {
            if let position = order[pairs[index].id] {
                pairs[index].sortOrder = position
            } else {
                pairs[index].sortOrder = fallbackBase + pairs[index].sortOrder
            }
        }
        persistence.savePairs(pairs)
    }

    // MARK: - Refresh loop

    /// Start the auto-refresh loop. Cancels any existing loop first.
    func startTimer() {
        stop()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.refreshInterval.seconds else { return }
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return // cancelled
                }
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    /// Stop the auto-refresh loop.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
