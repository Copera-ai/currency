import Foundation
import Testing
@testable import CoperaCurrency

/// Pure formatting / math tests — all synchronous, no network, no main actor.
struct RatesMathTests {
    // MARK: fmt buckets

    @Test func fmtLargeWithGrouping() {
        #expect(RatesStore.fmt(67842) == "67,842.00")
    }

    @Test func fmtMidTwoDecimals() {
        #expect(RatesStore.fmt(5.42) == "5.42")
    }

    @Test func fmtSubOneFourDecimals() {
        #expect(RatesStore.fmt(0.1845) == "0.1845")
    }

    @Test func fmtTinySixDecimals() {
        #expect(RatesStore.fmt(0.006357) == "0.006357")
    }

    @Test func fmtThousandsBoundary() {
        #expect(RatesStore.fmt(1234.5) == "1,234.50")
    }

    @Test func fmtNonFiniteEmDash() {
        #expect(RatesStore.fmt(.nan) == "—")
        #expect(RatesStore.fmt(.infinity) == "—")
    }

    // MARK: rate / convert

    private static let usdPerUnit: [String: Double] = [
        "USD": 1,
        "BRL": 0.1845,
        "EUR": 1.0830,
        "BTC": 67842,
    ]

    @Test func rateUsdToBrl() {
        let r = RatesStore.rate("USD", "BRL", in: Self.usdPerUnit)
        #expect(abs(r - (1 / 0.1845)) < 1e-9)
    }

    @Test func rateBtcToUsd() {
        #expect(RatesStore.rate("BTC", "USD", in: Self.usdPerUnit) == 67842)
    }

    @Test func convertUsdToBrl() {
        let v = RatesStore.convert(amount: 100, from: "USD", to: "BRL", in: Self.usdPerUnit)
        #expect(abs(v - (100 / 0.1845)) < 1e-9)
    }

    @Test func convertEurToBrlViaUsd() {
        // EUR -> BRL = amount * usd[EUR] / usd[BRL]
        let v = RatesStore.convert(amount: 1, from: "EUR", to: "BRL", in: Self.usdPerUnit)
        #expect(abs(v - (1.0830 / 0.1845)) < 1e-9)
    }

    // MARK: change

    @Test func changeIsBaseMinusQuote() {
        let changes: [String: Double] = ["USD": 0, "BRL": -0.31, "BTC": 2.14]
        #expect(RatesStore.change("USD", "BRL", in: changes) == 0 - (-0.31))
        #expect(RatesStore.change("BTC", "USD", in: changes) == 2.14)
    }
}
