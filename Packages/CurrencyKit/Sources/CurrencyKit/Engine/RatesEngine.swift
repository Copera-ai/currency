import Foundation

/// Fetches and merges rates from every source.
///
/// - Concurrent ``refresh(force:)`` calls share one in-flight fetch.
/// - Each source has its own TTL; a source fetched recently is reused, not refetched.
/// - A failing source backs off exponentially and keeps serving its last good values,
///   reported through ``RatesSnapshot/issues``.
/// - Fiat prices are live Coinbase exchange rates. The daily currency API is the
///   fallback (and the only source for the few currencies Coinbase lacks) and the
///   reference for the live change: live rate vs. the latest daily snapshot (00:00 UTC).
///   Daily-only currencies show the day-over-day change.
/// - Crypto change is Coinbase's 24h change.
public actor RatesEngine {
    /// Tuning knobs.
    public struct Configuration: Sendable {
        /// Reuse daily fiat data younger than this (the source publishes daily).
        public var fiatTTL: TimeInterval
        /// Reuse live fiat rates younger than this.
        public var liveFiatTTL: TimeInterval
        /// Reuse crypto data younger than this.
        public var cryptoTTL: TimeInterval
        /// First retry delay after a failure; doubles on each consecutive failure.
        public var backoffBase: TimeInterval
        /// Upper bound for the retry delay.
        public var backoffMax: TimeInterval

        /// Live TTLs sit below the shortest refresh interval (15 s) so every tick refetches.
        public init(
            fiatTTL: TimeInterval = 600,
            liveFiatTTL: TimeInterval = 10,
            cryptoTTL: TimeInterval = 10,
            backoffBase: TimeInterval = 30,
            backoffMax: TimeInterval = 900
        ) {
            self.fiatTTL = fiatTTL
            self.liveFiatTTL = liveFiatTTL
            self.cryptoTTL = cryptoTTL
            self.backoffBase = backoffBase
            self.backoffMax = backoffMax
        }
    }

    struct SourceHealth: Sendable {
        var lastSuccess: Date?
        var consecutiveFailures = 0
        var retryAt: Date?
        var lastError: CurrencyKitError?
    }

    private let fiat: FiatRatesService
    private let coinbase: CoinbaseService
    private let productIDs: [String]
    private let fiatCodes: Set<String>
    private let cache: DiskCache
    private let configuration: Configuration
    private let now: @Sendable () -> Date

    private var fiatLatest: FiatSnapshot?
    private var fiatPrevious: FiatSnapshot?
    /// Live fiat rates as units per USD (catalog fiat only).
    private var liveFiat: [String: Double] = [:]
    private var liveFiatFetchedAt: Date?
    private var tickers: [String: CoinbaseTicker] = [:]
    private var cryptoFetchedAt: Date?
    private var restored: RatesSnapshot?
    private var health: [RateSourceKind: SourceHealth] = [:]
    private var inFlight: (id: UUID, task: Task<RatesSnapshot, any Error>)?

    /// The latest snapshot produced (or restored from disk).
    public private(set) var current: RatesSnapshot?

    public init(
        http: any HTTPClient,
        cache: DiskCache,
        catalog: CurrencyCatalog = .shared,
        configuration: Configuration = Configuration(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        fiat = FiatRatesService(http: http, cache: cache, now: now)
        coinbase = CoinbaseService(http: http)
        productIDs = catalog.coinbaseProductIDs
        fiatCodes = Set(catalog.fiat.map { $0.code.uppercased() })
        self.cache = cache
        self.configuration = configuration
        self.now = now
    }

    /// Loads the last good snapshot from disk so the UI has something to show before
    /// the first network round trip. Its sources are treated as expired.
    @discardableResult
    public func restoreFromDisk() -> RatesSnapshot? {
        guard current == nil, let snapshot = cache.loadLastRates() else { return current }
        restored = snapshot
        current = snapshot
        return snapshot
    }

    /// Refreshes due sources and returns the merged snapshot.
    ///
    /// - Parameter force: ignore TTLs and backoff (manual refresh, wake, network restored).
    /// - Throws: ``CurrencyKitError`` only when no rates at all are available.
    public func refresh(force: Bool = false) async throws -> RatesSnapshot {
        if let inFlight {
            Log.engine.debug("Joining in-flight refresh")
            return try await inFlight.task.value
        }
        let id = UUID()
        let task = Task { try await self.performRefresh(force: force) }
        inFlight = (id, task)
        do {
            let snapshot = try await task.value
            finish(id)
            return snapshot
        } catch {
            finish(id)
            throw error
        }
    }

    /// Current backoff state of `source` (for diagnostics and tests).
    func sourceHealth(_ source: RateSourceKind) -> SourceHealth {
        health[source] ?? SourceHealth()
    }

    private func finish(_ id: UUID) {
        if inFlight?.id == id { inFlight = nil }
    }

    // MARK: - Refresh

    private func performRefresh(force: Bool) async throws -> RatesSnapshot {
        let started = now()
        let wantFiat = isDue(.fiat, ttl: configuration.fiatTTL, force: force, at: started)
        let wantLiveFiat = isDue(.liveFiat, ttl: configuration.liveFiatTTL, force: force, at: started)
        let wantCrypto = isDue(.crypto, ttl: configuration.cryptoTTL, force: force, at: started)
        Log.engine.info("Refresh (force: \(force)) fiat: \(wantFiat), live fiat: \(wantLiveFiat), crypto: \(wantCrypto)")

        let fiatService = fiat
        let previousCached = fiatPrevious
        let coinbaseService = coinbase
        let ids = productIDs
        let codes = fiatCodes
        async let fiatResult = wantFiat ? Self.loadFiat(fiatService, previousCached: previousCached) : nil
        async let liveFiatResult = wantLiveFiat ? Self.loadLiveFiat(coinbaseService, codes: codes) : nil
        async let cryptoResult = wantCrypto ? Self.loadCrypto(coinbaseService, productIDs: ids) : nil

        let completed = now()
        if let result = await fiatResult {
            switch result {
            case .success(let (latest, previous)):
                fiatLatest = latest
                fiatPrevious = previous
                recordSuccess(.fiat, at: completed)
            case .failure(let error):
                recordFailure(.fiat, error, at: completed)
            }
        }
        if let result = await liveFiatResult {
            switch result {
            case .success(let fresh):
                liveFiat = fresh
                liveFiatFetchedAt = completed
                recordSuccess(.liveFiat, at: completed)
            case .failure(let error):
                recordFailure(.liveFiat, error, at: completed)
            }
        }
        if let result = await cryptoResult {
            switch result {
            case .success(let fresh):
                tickers.merge(fresh) { _, new in new }
                cryptoFetchedAt = completed
                recordSuccess(.crypto, at: completed)
            case .failure(let error):
                recordFailure(.crypto, error, at: completed)
            }
        }

        let snapshot = merge(at: completed)
        guard snapshot.rates.keys.contains(where: { $0 != "USD" }) else {
            throw snapshot.issues[.fiat] ?? snapshot.issues[.crypto] ?? CurrencyKitError.noData
        }
        current = snapshot
        let fetchedSomething = [(wantFiat, RateSourceKind.fiat), (wantLiveFiat, .liveFiat), (wantCrypto, .crypto)]
            .contains { wanted, kind in wanted && health[kind]?.lastError == nil }
        if fetchedSomething {
            cache.saveLastRates(snapshot)
        }
        return snapshot
    }

    private static func loadFiat(
        _ service: FiatRatesService,
        previousCached: FiatSnapshot?
    ) async -> Result<(FiatSnapshot, FiatSnapshot?), CurrencyKitError> {
        do {
            let latest = try await service.latest()
            let previousDay = latest.day.adding(days: -1)
            if let previousCached, previousCached.day == previousDay {
                return .success((latest, previousCached))
            }
            do {
                return .success((latest, try await service.snapshot(for: previousDay)))
            } catch {
                Log.engine.error("Previous-day snapshot \(previousDay.description, privacy: .public) unavailable; fiat change unknown")
                return .success((latest, nil))
            }
        } catch {
            return .failure(CurrencyKitError(error))
        }
    }

    private static func loadLiveFiat(_ service: CoinbaseService, codes: Set<String>) async -> Result<[String: Double], CurrencyKitError> {
        do {
            let rates = try await service.exchangeRates().filter { codes.contains($0.key) && $0.key != "USD" }
            guard !rates.isEmpty else { return .failure(.noData) }
            return .success(rates)
        } catch {
            return .failure(CurrencyKitError(error))
        }
    }

    private static func loadCrypto(_ service: CoinbaseService, productIDs: [String]) async -> Result<[String: CoinbaseTicker], CurrencyKitError> {
        do {
            return .success(try await service.tickers(productIDs))
        } catch {
            return .failure(CurrencyKitError(error))
        }
    }

    // MARK: - Merge

    private func merge(at date: Date) -> RatesSnapshot {
        var rates = restored?.rates ?? [:]
        if let latest = fiatLatest {
            let asOf = latest.day.date
            for (code, units) in latest.unitsPerUSD {
                // Never replace a newer live value restored from disk with the daily one.
                if let existing = rates[code], existing.asOf > asOf { continue }
                let usdPerUnit = 1 / units
                let change = fiatPrevious?.usdPerUnit(code).flatMap { RateMath.change(from: $0, to: usdPerUnit) }
                rates[code] = AssetRate(usdPerUnit: usdPerUnit, change24h: change, asOf: asOf, source: .currencyAPI)
            }
        }
        if let fetchedAt = liveFiatFetchedAt {
            for (code, units) in liveFiat {
                let usdPerUnit = 1 / units
                // Change since the latest daily snapshot (00:00 UTC); unknown without one.
                let reference = fiatLatest?.usdPerUnit(code)
                let change = reference.flatMap { RateMath.change(from: $0, to: usdPerUnit) }
                rates[code] = AssetRate(usdPerUnit: usdPerUnit, change24h: change, asOf: fetchedAt, source: .coinbase)
            }
        }
        if let fetchedAt = cryptoFetchedAt {
            for (code, ticker) in tickers {
                rates[code] = AssetRate(usdPerUnit: ticker.price, change24h: ticker.change24h, asOf: fetchedAt, source: .coinbase)
            }
        }
        let fiatDay = fiatLatest?.day ?? restored?.fiatDay
        rates["USD"] = AssetRate(usdPerUnit: 1, change24h: 0, asOf: fiatDay?.date ?? date, source: .currencyAPI)

        var issues: [RateSourceKind: CurrencyKitError] = [:]
        for (kind, state) in health {
            if let error = state.lastError { issues[kind] = error }
        }
        // "Last updated" means the last time real data arrived, not this merge.
        let fetchedAt = health.values.compactMap(\.lastSuccess).max() ?? restored?.fetchedAt ?? date
        return RatesSnapshot(rates: rates, fetchedAt: fetchedAt, fiatDay: fiatDay, issues: issues)
    }

    // MARK: - TTL and backoff

    private func isDue(_ source: RateSourceKind, ttl: TimeInterval, force: Bool, at date: Date) -> Bool {
        if force { return true }
        let state = health[source] ?? SourceHealth()
        if let retryAt = state.retryAt, date < retryAt {
            Log.engine.debug("\(source.rawValue, privacy: .public) backing off until \(retryAt)")
            return false
        }
        guard let lastSuccess = state.lastSuccess, state.lastError == nil else { return true }
        return date.timeIntervalSince(lastSuccess) >= ttl
    }

    private func recordSuccess(_ source: RateSourceKind, at date: Date) {
        health[source] = SourceHealth(lastSuccess: date)
    }

    private func recordFailure(_ source: RateSourceKind, _ error: CurrencyKitError, at date: Date) {
        var state = health[source] ?? SourceHealth()
        state.consecutiveFailures += 1
        state.lastError = error
        state.retryAt = date.addingTimeInterval(Self.backoffDelay(failures: state.consecutiveFailures, configuration: configuration))
        health[source] = state
        Log.engine.error("\(source.rawValue, privacy: .public) failed (\(state.consecutiveFailures)x): \(error.localizedDescription, privacy: .public)")
    }

    /// `base * 2^(failures - 1)`, capped at `max`.
    static func backoffDelay(failures: Int, configuration: Configuration) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let exponent = Double(min(failures - 1, 16))
        return min(configuration.backoffBase * pow(2, exponent), configuration.backoffMax)
    }
}
