import Foundation

/// Builds price series for any pair by composing per-currency USD series.
///
/// - Crypto listed on Coinbase: Coinbase candles (24H at 15m, 7D hourly, 30D 6-hourly, 90D daily).
/// - Everything else: dated daily snapshots from the currency API (cached on disk forever),
///   sampled daily for 7D/30D and every third day for 90D. 24H is unavailable for pairs
///   without a live leg.
/// - Mixed pairs use the candle timeline and the most recent daily value at each time.
/// - Fiat legs use Coinbase's live exchange rate after today's 00:00 UTC snapshot, and
///   fiat-only series end with a live point at "now", so charts end at the price shown.
public actor HistoryService {
    private enum Leg: Hashable {
        case usd
        case coinbase(String)
        case daily(String)
    }

    /// Live fiat rates (units per USD) and the moment they take over from daily data.
    private struct LiveFiat {
        let unitsPerUSD: [String: Double]
        let since: Date
    }

    private struct Key: Hashable {
        let pair: CurrencyPair
        let range: HistoryRange
    }

    private let fiat: FiatRatesService
    private let coinbase: CoinbaseService
    private let catalog: CurrencyCatalog
    private let now: @Sendable () -> Date
    private let maxConcurrentDownloads = 6

    private var memo: [Key: (history: PairHistory, expires: Date)] = [:]
    private var inFlight: [Key: Task<PairHistory, any Error>] = [:]
    private var dailyMemory: [CalendarDay: FiatSnapshot] = [:]

    public init(
        http: any HTTPClient,
        cache: DiskCache,
        catalog: CurrencyCatalog = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        fiat = FiatRatesService(http: http, cache: cache, now: now)
        coinbase = CoinbaseService(http: http)
        self.catalog = catalog
        self.now = now
    }

    /// The series for `pair` over `range`, oldest point first.
    ///
    /// Results are memoized briefly (1 min, since every series ends live) and
    /// concurrent identical requests share one fetch.
    /// - Throws: ``CurrencyKitError/historyUnavailable`` for 24H on pairs without a
    ///   Coinbase leg; other ``CurrencyKitError``s when nothing could be fetched.
    public func history(for pair: CurrencyPair, range: HistoryRange) async throws -> PairHistory {
        let key = Key(pair: pair, range: range)
        if let cached = memo[key], cached.expires > now() { return cached.history }
        if let task = inFlight[key] { return try await task.value }

        let task = Task { try await self.build(pair: pair, range: range) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let history = try await task.value
        memo[key] = (history, now().addingTimeInterval(60))
        return history
    }

    // MARK: - Building

    private func leg(_ code: String) -> Leg {
        if code == "USD" { return .usd }
        if let product = catalog.currency(for: code)?.coinbaseProductID { return .coinbase(product) }
        return .daily(code)
    }

    private func build(pair: CurrencyPair, range: HistoryRange) async throws -> PairHistory {
        let legs = [leg(pair.base), leg(pair.quote)]
        let products = legs.compactMap { leg -> String? in
            if case .coinbase(let id) = leg { return id }
            return nil
        }
        let needsDaily = legs.contains { if case .daily = $0 { true } else { false } }
        if products.isEmpty && range == .day { throw CurrencyKitError.historyUnavailable }

        let end = now()
        let start = end.addingTimeInterval(-range.duration)
        async let candleSeries = Self.loadCandles(coinbase, products: products, range: range, start: start, end: end)
        async let liveRates = needsDaily ? Self.loadLiveFiat(coinbase) : nil
        let daily = needsDaily ? try await dailySamples(for: range, endingAt: end) : []
        let series = try await candleSeries
        let live = await liveRates.map { LiveFiat(unitsPerUSD: $0, since: CalendarDay(end).date) }

        let times: [Date]
        if products.isEmpty {
            times = daily.map(\.day.date) + (live == nil ? [] : [end])
        } else {
            let sets = products.compactMap { series[$0].map { Set($0.keys) } }
            times = (sets.dropFirst().reduce(sets.first ?? []) { $0.intersection($1) }).sorted()
        }

        let points = times.compactMap { time -> HistoryPoint? in
            guard let base = value(of: legs[0], at: time, series: series, daily: daily, live: live),
                  let quote = value(of: legs[1], at: time, series: series, daily: daily, live: live),
                  let price = RateMath.crossRate(baseUSDPerUnit: base, quoteUSDPerUnit: quote) else {
                return nil
            }
            return HistoryPoint(date: time, value: price)
        }
        guard !points.isEmpty else { throw CurrencyKitError.noData }

        var sources: [RateSource] = []
        if !products.isEmpty { sources.append(.coinbase) }
        if needsDaily { sources.append(.currencyAPI) }
        if live != nil, !sources.contains(.coinbase) { sources.append(.coinbase) }
        if sources.isEmpty { sources.append(.currencyAPI) }
        return PairHistory(pair: pair, range: range, points: points, sources: sources.sorted { $0.rawValue < $1.rawValue })
    }

    private func value(
        of leg: Leg,
        at time: Date,
        series: [String: [Date: Double]],
        daily: [(day: CalendarDay, snapshot: FiatSnapshot)],
        live: LiveFiat?
    ) -> Double? {
        switch leg {
        case .usd:
            return 1
        case .coinbase(let product):
            return series[product]?[time]
        case .daily(let code):
            if let live, time > live.since, let units = live.unitsPerUSD[code], units > 0 {
                return 1 / units
            }
            // The most recent sample on or before `time`, else the earliest one.
            let day = CalendarDay(time)
            let sample = daily.last { $0.day <= day } ?? daily.first
            return sample?.snapshot.usdPerUnit(code)
        }
    }

    /// Live fiat rates, or `nil` when Coinbase is unavailable (the series then ends at
    /// the latest daily snapshot).
    private static func loadLiveFiat(_ service: CoinbaseService) async -> [String: Double]? {
        do {
            return try await service.exchangeRates()
        } catch {
            Log.history.notice("Live fiat rates unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func loadCandles(
        _ service: CoinbaseService,
        products: [String],
        range: HistoryRange,
        start: Date,
        end: Date
    ) async throws -> [String: [Date: Double]] {
        var result: [String: [Date: Double]] = [:]
        for product in Set(products) {
            let candles = try await service.candles(productID: product, granularity: range.candleGranularity, start: start, end: end)
            result[product] = Dictionary(candles.map { ($0.time, $0.close) }) { _, last in last }
        }
        return result
    }

    /// Daily snapshots covering `range`, oldest first. Individual missing days are skipped.
    private func dailySamples(for range: HistoryRange, endingAt end: Date) async throws -> [(day: CalendarDay, snapshot: FiatSnapshot)] {
        let today = CalendarDay(end)
        let first = max(today.adding(days: -range.days), Endpoints.earliestFiatDay)
        var days: [CalendarDay] = []
        var cursor = today
        while cursor >= first {
            days.append(cursor)
            cursor = cursor.adding(days: -range.dailySampleStep)
        }
        if let last = days.last, last != first { days.append(first) }

        var found: [CalendarDay: FiatSnapshot] = [:]
        var missing: [CalendarDay] = []
        for day in days {
            if let snapshot = dailyMemory[day] { found[day] = snapshot } else { missing.append(day) }
        }

        let (downloaded, firstError) = await download(missing)
        for (day, snapshot) in downloaded {
            found[day] = snapshot
            if day < today { dailyMemory[day] = snapshot }
        }
        if dailyMemory.count > 400 { dailyMemory.removeAll() }

        guard !found.isEmpty else { throw firstError ?? CurrencyKitError.noData }
        return found.sorted { $0.key < $1.key }.map { (day: $0.key, snapshot: $0.value) }
    }

    /// Downloads `days` with bounded concurrency.
    private func download(_ days: [CalendarDay]) async -> ([CalendarDay: FiatSnapshot], CurrencyKitError?) {
        let service = fiat
        let limit = maxConcurrentDownloads
        return await withTaskGroup(of: (CalendarDay, Result<FiatSnapshot, CurrencyKitError>).self) { group in
            var pending = days[...]
            func enqueue() {
                guard let day = pending.popFirst() else { return }
                group.addTask {
                    do {
                        return (day, .success(try await service.snapshot(for: day)))
                    } catch {
                        return (day, .failure(CurrencyKitError(error)))
                    }
                }
            }
            for _ in 0..<limit { enqueue() }

            var snapshots: [CalendarDay: FiatSnapshot] = [:]
            var firstError: CurrencyKitError?
            for await (day, result) in group {
                switch result {
                case .success(let snapshot): snapshots[day] = snapshot
                case .failure(let error):
                    Log.history.notice("Daily snapshot \(day.description, privacy: .public) unavailable: \(error.localizedDescription, privacy: .public)")
                    if firstError == nil || error.isConnectivity { firstError = error }
                }
                enqueue()
            }
            return (snapshots, firstError)
        }
    }
}
