@testable import CurrencyKit
import Foundation
import Testing

@Suite("Endpoint decoding")
struct DecodingTests {
    @Test func fiatLatestFixture() throws {
        let snapshot = try FiatSnapshot.decode(try Fixture.data("fiat-latest"))
        #expect(snapshot.day == CalendarDay(year: 2026, month: 11, day: 3))
        #expect(snapshot.unitsPerUSD.count > 300)
        #expect(snapshot.unitsPerUSD["USD"] == 1)
        #expect(snapshot.unitsPerUSD["BRL"] == 5.44059239)
        #expect(snapshot.unitsPerUSD["brl"] == nil, "keys are uppercased")
        // Exponent notation (1.3077279e-05) decodes.
        #expect(approx(snapshot.unitsPerUSD["BTC"], 1.3077279e-05))
        #expect(approx(snapshot.usdPerUnit("BRL"), 1 / 5.44059239))
    }

    @Test func fiatDatedAndFallbackFixtures() throws {
        let dated = try FiatSnapshot.decode(try Fixture.data("fiat-2026-11-02"))
        #expect(dated.day.description == "2026-11-02")
        #expect(dated.unitsPerUSD["BRL"] == 5.43870352)

        let jsdelivr = try FiatSnapshot.decode(try Fixture.data("fiat-latest-jsdelivr"))
        #expect(jsdelivr.unitsPerUSD.count > 300)
    }

    @Test func coinbaseExchangeRates() throws {
        let rates = try CoinbaseExchangeRates.decode(try Fixture.data("coinbase-exchange-rates"))
        #expect(rates["BRL"] == 5.499)
        #expect(rates["EUR"] == 0.893466)
        #expect(rates["BOGUS"] == nil && rates["ZERO"] == nil, "invalid entries are skipped")

        let euroBase = Data(#"{"data":{"currency":"EUR","rates":{"BRL":"6.1"}}}"#.utf8)
        #expect(throws: CurrencyKitError.self) { try CoinbaseExchangeRates.decode(euroBase) }
        let empty = Data(#"{"data":{"currency":"USD","rates":{}}}"#.utf8)
        #expect(throws: CurrencyKitError.self) { try CoinbaseExchangeRates.decode(empty) }
    }

    @Test func fiatSkipsInvalidEntriesWithoutFailing() throws {
        let json = #"{"date":"2026-11-03","usd":{"brl":5.4,"bad":"x","nil":null,"zero":0,"neg":-1}}"#
        let snapshot = try FiatSnapshot.decode(Data(json.utf8))
        #expect(Set(snapshot.unitsPerUSD.keys) == ["USD", "BRL"])
    }

    @Test(arguments: [
        #"{"usd":{"brl":5.4}}"#,
        #"{"date":"yesterday","usd":{"brl":5.4}}"#,
        #"{"date":"2026-11-03","usd":{}}"#,
        "<html>Rate limited</html>",
    ])
    func fiatRejectsMalformedPayloads(_ json: String) {
        #expect(throws: CurrencyKitError.self) { try FiatSnapshot.decode(Data(json.utf8)) }
    }

    @Test func coinbaseProductsFixture() throws {
        let tickers = try CoinbaseTicker.decodeList(try Fixture.data("coinbase-products"))
        #expect(tickers.map(\.productID) == ["BTC-USD", "ETH-USD", "SOL-USD"])
        let btc = try #require(tickers.first)
        #expect(btc.baseCode == "BTC")
        #expect(btc.price == 76372.94)
        // Percent → fraction.
        #expect(approx(btc.change24h, -0.021701707235811))
    }

    @Test func coinbaseEmptyAndLossyProducts() throws {
        #expect(try CoinbaseTicker.decodeList(try Fixture.data("coinbase-products-empty")).isEmpty)

        let json = #"""
        {"products":[
          {"product_id":"BTC-USD","price":"70000","price_percentage_change_24h":"1.5"},
          {"product_id":"BAD-USD","price":"not a number","price_percentage_change_24h":"1"},
          {"product_id":"ODD-USD"},
          {"product_id":"ETH-USD","price":"2000","price_percentage_change_24h":""}
        ]}
        """#
        let tickers = try CoinbaseTicker.decodeList(Data(json.utf8))
        #expect(tickers.map(\.productID) == ["BTC-USD", "ETH-USD"])
        #expect(approx(tickers[0].change24h, 0.015))
        #expect(tickers[1].change24h == nil)
    }

    @Test func coinbaseCandlesFixtures() throws {
        let hourly = try Candle.decodeList(try Fixture.data("coinbase-candles-hourly"))
        #expect(hourly.count >= 24)
        #expect(hourly.map(\.time) == hourly.map(\.time).sorted(), "returned oldest first")
        let newest = try #require(hourly.last)
        #expect(newest.time == Date(timeIntervalSince1970: 1_793_685_600))
        #expect(newest.close == 76372.95)
        #expect(newest.low <= newest.close && newest.close <= newest.high)

        let daily = try Candle.decodeList(try Fixture.data("coinbase-candles-daily"))
        #expect(daily.count >= 7)
        #expect(zip(daily, daily.dropFirst()).allSatisfy { $1.time.timeIntervalSince($0.time) == 86_400 })
    }

    @Test func coinbaseErrorBodyIsNotCandles() throws {
        #expect(throws: CurrencyKitError.self) { try Candle.decodeList(try Fixture.data("coinbase-notfound")) }
    }

    @Test func calendarDayParsingAndArithmetic() throws {
        let day = try #require(CalendarDay(string: "2024-03-01"))
        #expect(day.adding(days: 1).description == "2024-03-02")
        #expect(CalendarDay(string: "2024-02-29")?.adding(days: 1).description == "2024-03-01")
        #expect(CalendarDay(string: "2026-01-01")?.adding(days: -1).description == "2025-12-31")
        #expect(CalendarDay(string: "2026-13-01") == nil)
        #expect(CalendarDay(fixtureNow).description == "2026-11-03")
        #expect(CalendarDay(string: "2026-11-03")?.date == Date(timeIntervalSince1970: 1_793_664_000))
    }
}
