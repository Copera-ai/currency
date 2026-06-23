import Foundation
import Testing
@testable import CoperaCurrency

/// Persistence + first-launch seeding tests over isolated UserDefaults suites.
struct PersistenceTests {
    @Test func firstLaunchSeedsDefaultPairs() {
        let (defaults, suite) = TestSupport.freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PersistenceStore(suiteName: suite)
        let pairs = store.loadPairs()

        #expect(pairs.count == 7)
        #expect(pairs == CurrencyPair.defaultPairs)

        // Spot-check a few entries for ids/base/quote/flags.
        #expect(pairs[0].id == 1)
        #expect(pairs[0].base == "USD")
        #expect(pairs[0].quote == "BRL")
        #expect(pairs[0].isFavorite)
        #expect(pairs[0].isTracked)

        #expect(pairs[1].base == "BTC")
        #expect(pairs[1].quote == "USD")
        #expect(pairs[1].isFavorite)

        #expect(pairs[5].base == "GBP")
        #expect(!pairs[5].isTracked)

        // Seeding must have persisted: a second load returns the same without
        // re-seeding logic firing differently.
        let again = store.loadPairs()
        #expect(again == pairs)
    }

    @Test func savedPairsRoundTrip() {
        let (defaults, suite) = TestSupport.freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PersistenceStore(suiteName: suite)
        var pairs = store.loadPairs()
        pairs[0].isFavorite = false
        store.savePairs(pairs)

        let reloaded = store.loadPairs()
        #expect(reloaded[0].isFavorite == false)
    }

    @Test func snapshotRoundTrip() {
        let (defaults, suite) = TestSupport.freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PersistenceStore(suiteName: suite)
        #expect(store.loadLastGood() == nil)

        let snapshot = RatesSnapshot(
            rates: ["BRL": NormalizedRate(usdPerUnit: 0.1845, change24h: -0.31)],
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            fiatDate: "2025-06-01"
        )
        store.saveLastGood(snapshot)
        let loaded = store.loadLastGood()
        #expect(loaded?.rates["BRL"]?.usdPerUnit == 0.1845)
        #expect(loaded?.fiatDate == "2025-06-01")
    }

    @Test func lastFiatFetchRoundTrip() {
        let (defaults, suite) = TestSupport.freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PersistenceStore(suiteName: suite)
        #expect(store.loadLastFiatFetch() == nil)

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.saveLastFiatFetch(date)
        #expect(store.loadLastFiatFetch() == date)
    }
}
