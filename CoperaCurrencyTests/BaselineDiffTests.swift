import Foundation
import Testing
@testable import CoperaCurrency

/// 24h baseline diff + rolling tests — pure functions, no network.
struct BaselineDiffTests {
    @Test func change24hAgainstBaseline() {
        let baseline = RatesSnapshot(
            rates: ["BRL": NormalizedRate(usdPerUnit: 0.18, change24h: 0)],
            updatedAt: Date(),
            fiatDate: "2025-06-01"
        )
        let changes = RatesStore.computeChange24h(now: ["BRL": 0.1845], baseline: baseline)
        let brl = changes["BRL"] ?? .nan
        #expect(abs(brl - 2.5) < 1e-9) // (0.1845/0.18 - 1)*100
    }

    @Test func change24hColdStartIsZero() {
        let changes = RatesStore.computeChange24h(now: ["BRL": 0.1845], baseline: nil)
        #expect(changes["BRL"] == 0)
    }

    @Test func change24hMissingCodeInBaselineIsZero() {
        let baseline = RatesSnapshot(
            rates: ["EUR": NormalizedRate(usdPerUnit: 1.0, change24h: 0)],
            updatedAt: Date(),
            fiatDate: nil
        )
        let changes = RatesStore.computeChange24h(now: ["BRL": 0.1845], baseline: baseline)
        #expect(changes["BRL"] == 0)
    }

    @Test func baselineRollsWhenMissing() {
        let result = RatesStore.resolvedBaseline(
            now: ["USD": 1, "BRL": 0.1845],
            stored: nil,
            newFiatDate: "2025-06-01",
            at: Date()
        )
        #expect(result.didRoll)
        #expect(result.snapshot.rates["BRL"]?.usdPerUnit == 0.1845)
    }

    @Test func baselineRollsWhenOlderThan24h() {
        let old = RatesSnapshot(
            rates: ["BRL": NormalizedRate(usdPerUnit: 0.18, change24h: 0)],
            updatedAt: Date(timeIntervalSinceNow: -90000), // > 86400s ago
            fiatDate: "2025-05-31"
        )
        let result = RatesStore.resolvedBaseline(
            now: ["BRL": 0.1845],
            stored: old,
            newFiatDate: "2025-06-01",
            at: Date()
        )
        #expect(result.didRoll)
        #expect(result.snapshot.rates["BRL"]?.usdPerUnit == 0.1845)
    }

    @Test func baselineRollsWhenFiatDateChanged() {
        let stored = RatesSnapshot(
            rates: ["BRL": NormalizedRate(usdPerUnit: 0.18, change24h: 0)],
            updatedAt: Date(),
            fiatDate: "2025-05-31"
        )
        let result = RatesStore.resolvedBaseline(
            now: ["BRL": 0.1845],
            stored: stored,
            newFiatDate: "2025-06-01",
            at: Date()
        )
        #expect(result.didRoll)
    }

    @Test func baselineHeldWhenFreshAndSameDate() {
        let stored = RatesSnapshot(
            rates: ["BRL": NormalizedRate(usdPerUnit: 0.18, change24h: 0)],
            updatedAt: Date(),
            fiatDate: "2025-06-01"
        )
        let result = RatesStore.resolvedBaseline(
            now: ["BRL": 0.1845],
            stored: stored,
            newFiatDate: "2025-06-01",
            at: Date()
        )
        #expect(!result.didRoll)
        #expect(result.snapshot.rates["BRL"]?.usdPerUnit == 0.18) // unchanged
    }
}
