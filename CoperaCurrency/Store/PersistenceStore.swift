import Foundation

/// Thin persistence layer over `UserDefaults` for the rates app.
///
/// All keys are namespaced under `com.copera.currency.`. Codable values are
/// stored as JSON `Data`.
///
/// `UserDefaults` is thread-safe but not (yet) marked `Sendable` by Foundation.
/// To make this store cleanly `Sendable` under Swift 6 strict concurrency
/// without unsafe escapes, it stores only the suite *name* (a `String`, which is
/// `Sendable`) and resolves the shared `UserDefaults` instance on demand. The
/// instance returned by `UserDefaults(suiteName:)` for a given name is a shared,
/// thread-safe singleton, so no mutable cross-actor state is captured.
struct PersistenceStore: Sendable {
    /// Key namespace prefix.
    static let namespace = "com.copera.currency."

    /// Fully-qualified UserDefaults keys.
    enum Key {
        static let pairs = namespace + "pairs"
        static let lastGood = namespace + "snapshot.lastGood"
        static let dailyBaseline = namespace + "snapshot.dailyBaseline"
        static let lastFiatFetch = namespace + "lastFiatFetch"
        static let refreshInterval = namespace + "refreshInterval"
    }

    /// The UserDefaults suite name; `nil` means `.standard`.
    private let suiteName: String?

    /// Default initializer using the standard defaults.
    init() {
        self.suiteName = nil
    }

    /// Initialize against a named suite (used by tests for isolation).
    init(suiteName: String) {
        self.suiteName = suiteName
    }

    /// Resolve the shared, thread-safe `UserDefaults` for this store.
    var defaults: UserDefaults {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            return suite
        }
        return .standard
    }

    private var encoder: JSONEncoder { JSONEncoder() }
    private var decoder: JSONDecoder { JSONDecoder() }

    // MARK: - Pairs

    /// Load the tracked pairs. On first launch (no stored value) this seeds and
    /// persists ``CurrencyPair/defaultPairs`` and returns them.
    func loadPairs() -> [CurrencyPair] {
        guard let data = defaults.data(forKey: Key.pairs),
              let pairs = try? decoder.decode([CurrencyPair].self, from: data) else {
            let seed = CurrencyPair.defaultPairs
            savePairs(seed)
            return seed
        }
        return pairs
    }

    func savePairs(_ pairs: [CurrencyPair]) {
        guard let data = try? encoder.encode(pairs) else { return }
        defaults.set(data, forKey: Key.pairs)
    }

    // MARK: - Last-good snapshot

    func loadLastGood() -> RatesSnapshot? {
        decodeSnapshot(forKey: Key.lastGood)
    }

    func saveLastGood(_ snapshot: RatesSnapshot) {
        encodeSnapshot(snapshot, forKey: Key.lastGood)
    }

    // MARK: - Daily baseline snapshot

    func loadDailyBaseline() -> RatesSnapshot? {
        decodeSnapshot(forKey: Key.dailyBaseline)
    }

    func saveDailyBaseline(_ snapshot: RatesSnapshot) {
        encodeSnapshot(snapshot, forKey: Key.dailyBaseline)
    }

    // MARK: - Last fiat fetch timestamp

    func loadLastFiatFetch() -> Date? {
        defaults.object(forKey: Key.lastFiatFetch) as? Date
    }

    func saveLastFiatFetch(_ date: Date) {
        defaults.set(date, forKey: Key.lastFiatFetch)
    }

    // MARK: - Refresh interval

    func loadRefreshIntervalRaw() -> Int? {
        defaults.object(forKey: Key.refreshInterval) as? Int
    }

    func saveRefreshIntervalRaw(_ raw: Int) {
        defaults.set(raw, forKey: Key.refreshInterval)
    }

    // MARK: - Helpers

    private func decodeSnapshot(forKey key: String) -> RatesSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(RatesSnapshot.self, from: data)
    }

    private func encodeSnapshot(_ snapshot: RatesSnapshot, forKey key: String) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
