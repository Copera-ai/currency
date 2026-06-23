import Foundation
import Testing
@testable import CoperaCurrency

/// RatesStore integration tests using injected mock providers (no network).
@MainActor
struct RatesStoreTests {
    private func makeStore(
        fiat: MockRatesProvider,
        crypto: MockRatesProvider
    ) -> (store: RatesStore, persistence: PersistenceStore, suite: String, defaults: UserDefaults) {
        let (defaults, suite) = TestSupport.freshDefaults()
        let persistence = PersistenceStore(suiteName: suite)
        let store = RatesStore(fiatProvider: fiat, cryptoProvider: crypto, persistence: persistence)
        return (store, persistence, suite, defaults)
    }

    @Test func refreshPopulatesRatesAndPersistsLastGood() async {
        let fiat = MockRatesProvider(map: ["USD": 1, "BRL": 0.1845, "EUR": 1.083])
        let crypto = MockRatesProvider(map: ["BTC": 67842, "ETH": 3521])
        let env = makeStore(fiat: fiat, crypto: crypto)
        defer { env.defaults.removePersistentDomain(forName: env.suite) }

        await env.store.refresh()

        #expect(env.store.rates["BTC"]?.usdPerUnit == 67842)
        #expect(env.store.rates["BRL"]?.usdPerUnit == 0.1845)
        #expect(env.store.rates["USD"]?.usdPerUnit == 1)
        #expect(env.store.lastUpdated != nil)
        #expect(env.store.loadState == .loaded)

        // Last-good persisted and decodable.
        let lastGood = env.persistence.loadLastGood()
        #expect(lastGood?.rates["BTC"]?.usdPerUnit == 67842)
        #expect(lastGood?.rates["BRL"]?.usdPerUnit == 0.1845)
    }

    @Test func refreshGoesStaleWhenFiatThrowsButKeepsOldFiat() async {
        // First, a fully successful refresh to establish data.
        let goodFiat = MockRatesProvider(map: ["USD": 1, "BRL": 0.1845])
        let goodCrypto = MockRatesProvider(map: ["BTC": 67842])
        let env = makeStore(fiat: goodFiat, crypto: goodCrypto)
        defer { env.defaults.removePersistentDomain(forName: env.suite) }

        await env.store.refresh()
        #expect(env.store.loadState == .loaded)
        #expect(env.store.rates["BRL"]?.usdPerUnit == 0.1845)

        // Now rebuild a store sharing the same persistence so existing data is
        // present, but with a THROWING fiat provider and a working crypto one.
        // The fiat fetch was just recorded, so it would be hourly-gated; to
        // exercise the throw path we clear the last-fiat-fetch marker by using a
        // fresh store on the same defaults and forcing a throw.
        env.defaults.removeObject(forKey: PersistenceStore.Key.lastFiatFetch)

        let throwingFiat = MockRatesProvider(shouldThrow: true)
        let workingCrypto = MockRatesProvider(map: ["BTC": 70000])
        let store2 = RatesStore(fiatProvider: throwingFiat, cryptoProvider: workingCrypto, persistence: env.persistence)

        // store2 loaded last-good on init, so it has BRL=0.1845 already.
        #expect(store2.rates["BRL"]?.usdPerUnit == 0.1845)

        await store2.refresh()

        // Fiat threw → stale; crypto updated; old fiat retained.
        if case .stale = store2.loadState {
            // ok
        } else {
            Issue.record("Expected .stale, got \(store2.loadState)")
        }
        #expect(store2.rates["BTC"]?.usdPerUnit == 70000)
        #expect(store2.rates["BRL"]?.usdPerUnit == 0.1845)
    }

    @Test func refreshOfflineWhenEverythingFailsAndNoData() async {
        let throwingFiat = MockRatesProvider(shouldThrow: true)
        let throwingCrypto = MockRatesProvider(shouldThrow: true)
        let env = makeStore(fiat: throwingFiat, crypto: throwingCrypto)
        defer { env.defaults.removePersistentDomain(forName: env.suite) }

        await env.store.refresh()

        // No existing data + everything failed → offline.
        #expect(env.store.loadState == .offline)
    }

    // MARK: addPair validation

    @Test func addPairRejectsSameBaseQuote() {
        let env = makeStore(fiat: MockRatesProvider(), crypto: MockRatesProvider())
        defer { env.defaults.removePersistentDomain(forName: env.suite) }

        let before = env.store.pairs.count
        let ok = env.store.addPair(base: "USD", quote: "USD")
        #expect(ok == false)
        #expect(env.store.pairs.count == before)
    }

    @Test func addPairRejectsDuplicate() {
        let env = makeStore(fiat: MockRatesProvider(), crypto: MockRatesProvider())
        defer { env.defaults.removePersistentDomain(forName: env.suite) }

        // USD/BRL is a seeded pair.
        let before = env.store.pairs.count
        let ok = env.store.addPair(base: "USD", quote: "BRL")
        #expect(ok == false)
        #expect(env.store.pairs.count == before)
    }

    @Test func addPairAppendsValidDistinctPair() {
        let env = makeStore(fiat: MockRatesProvider(), crypto: MockRatesProvider())
        defer { env.defaults.removePersistentDomain(forName: env.suite) }

        let before = env.store.pairs.count
        let ok = env.store.addPair(base: "GBP", quote: "EUR")
        #expect(ok == true)
        #expect(env.store.pairs.count == before + 1)

        let added = env.store.pairs.last!
        #expect(added.base == "GBP")
        #expect(added.quote == "EUR")
        #expect(added.isTracked)
        #expect(added.id == 8) // maxId(7) + 1

        // Persisted.
        let reloaded = env.persistence.loadPairs()
        #expect(reloaded.contains { $0.base == "GBP" && $0.quote == "EUR" })
    }

    @Test func toggleFavoriteAndTrackedPersist() {
        let env = makeStore(fiat: MockRatesProvider(), crypto: MockRatesProvider())
        defer { env.defaults.removePersistentDomain(forName: env.suite) }

        env.store.toggleFavorite(3) // EUR/BRL starts false
        #expect(env.store.pairs.first { $0.id == 3 }?.isFavorite == true)

        env.store.toggleTracked(6) // GBP/USD starts untracked
        #expect(env.store.pairs.first { $0.id == 6 }?.isTracked == true)

        let reloaded = env.persistence.loadPairs()
        #expect(reloaded.first { $0.id == 3 }?.isFavorite == true)
        #expect(reloaded.first { $0.id == 6 }?.isTracked == true)
    }

    @Test func trackedSortedPutsFavoritesFirst() {
        let env = makeStore(fiat: MockRatesProvider(), crypto: MockRatesProvider())
        defer { env.defaults.removePersistentDomain(forName: env.suite) }

        let sorted = env.store.trackedSorted
        // All favorites must come before all non-favorites.
        let firstNonFav = sorted.firstIndex { !$0.isFavorite } ?? sorted.count
        let lastFav = sorted.lastIndex { $0.isFavorite } ?? -1
        #expect(lastFav < firstNonFav)
        // All tracked only.
        let allTracked = sorted.allSatisfy { $0.isTracked }
        #expect(allTracked)
    }
}
