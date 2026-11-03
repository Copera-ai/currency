@testable import CurrencyKit
import Foundation
import Testing

@Suite("Rate math")
struct RateMathTests {
    private static let usdPerUnit: [String: Double] = ["USD": 1, "BRL": 0.1845, "EUR": 1.0830, "BTC": 67842]

    @Test func crossRates() {
        #expect(approx(RateMath.crossRate(baseUSDPerUnit: 1, quoteUSDPerUnit: 0.1845), 1 / 0.1845))
        #expect(RateMath.crossRate(baseUSDPerUnit: 67842, quoteUSDPerUnit: 1) == 67842)
        #expect(RateMath.crossRate(baseUSDPerUnit: 1, quoteUSDPerUnit: 0) == nil)
        #expect(RateMath.crossRate(baseUSDPerUnit: .nan, quoteUSDPerUnit: 1) == nil)
    }

    @Test func convertGoesThroughUSD() {
        #expect(approx(RateMath.convert(100, fromUSDPerUnit: 1, toUSDPerUnit: 0.1845), 100 / 0.1845))
        #expect(approx(RateMath.convert(1, fromUSDPerUnit: 1.0830, toUSDPerUnit: 0.1845), 1.0830 / 0.1845))
    }

    @Test func pairChangeComposesInsteadOfSubtracting() throws {
        // BTC +10% vs USD, BRL −5% vs USD → BTC/BRL = 1.10 / 0.95 − 1 = +15.79%, not +15%.
        let change = try #require(RateMath.pairChange(base: 0.10, quote: -0.05))
        #expect(approx(change, 1.10 / 0.95 - 1))
        #expect(abs(change - 0.15) > 0.005)
        // USD/BRL when BRL weakens 0.31%: USD buys more BRL.
        #expect(approx(RateMath.pairChange(base: 0, quote: -0.0031), 1 / (1 - 0.0031) - 1))
        #expect(RateMath.pairChange(base: 0.01, quote: nil) == nil)
    }

    @Test(arguments: [(0.05, -0.02), (-0.3, 0.12), (0.0, 0.0), (1.5, -0.4)])
    func invertedPairChangeIsConsistent(base: Double, quote: Double) throws {
        let forward = try #require(RateMath.pairChange(base: base, quote: quote))
        let inverse = try #require(RateMath.pairChange(base: quote, quote: base))
        #expect(approx((1 + forward) * (1 + inverse), 1))
    }

    @Test func snapshotQuoteMergesLegs() throws {
        let fiatDay = Date(timeIntervalSince1970: 1_793_664_000)
        let live = fiatDay.addingTimeInterval(3_600)
        let snapshot = RatesSnapshot(rates: [
            "USD": AssetRate(usdPerUnit: 1, change24h: 0, asOf: fiatDay, source: .currencyAPI),
            "BRL": AssetRate(usdPerUnit: 0.1845, change24h: -0.0031, asOf: fiatDay, source: .currencyAPI),
            "BTC": AssetRate(usdPerUnit: 67842, change24h: 0.0214, asOf: live, source: .coinbase),
        ], fetchedAt: live)

        let usdBRL = try #require(snapshot.quote(for: CurrencyPair(base: "USD", quote: "BRL")))
        #expect(approx(usdBRL.price, 1 / 0.1845))
        #expect(usdBRL.sources == [.currencyAPI])
        #expect(usdBRL.trend == .up)

        let btcUSD = try #require(snapshot.quote(for: CurrencyPair(base: "btc", quote: "usd")))
        #expect(btcUSD.price == 67842)
        #expect(btcUSD.asOf == live, "USD does not drag freshness down")
        #expect(btcUSD.sources == [.coinbase])

        let btcBRL = try #require(snapshot.quote(for: CurrencyPair(base: "BTC", quote: "BRL")))
        #expect(approx(btcBRL.price, 67842 / 0.1845))
        #expect(approx(btcBRL.change24h, 1.0214 / (1 - 0.0031) - 1))
        #expect(btcBRL.asOf == fiatDay, "oldest leg wins")
        #expect(btcBRL.sources == [.coinbase, .currencyAPI])

        #expect(snapshot.quote(for: CurrencyPair(base: "USD", quote: "XYZ")) == nil)
        #expect(approx(snapshot.convert(100, from: "USD", to: "BRL"), 100 / 0.1845))
    }

    @Test func trendThresholds() {
        #expect(Trend(change: 0.01) == .up)
        #expect(Trend(change: -0.01) == .down)
        #expect(Trend(change: 0) == .flat)
        #expect(Trend(change: nil) == .flat)
        #expect(Trend(change: .nan) == .flat)
        #expect(Trend(change: 0.000_01) == .flat, "rounds to 0.00%")
        #expect(Trend.up.arrow == "▲" && Trend.down.arrow == "▼" && Trend.flat.arrow == nil)
    }
}
