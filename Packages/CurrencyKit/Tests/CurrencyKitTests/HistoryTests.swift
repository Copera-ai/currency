@testable import CurrencyKit
import Foundation
import Testing

@Suite("History")
struct HistoryTests {
    /// Serves a dated snapshot for any day with BRL = 5 + dayOfMonth/100 and EUR = 0.9.
    private func dailyRoutes(_ http: FakeHTTPClient, missing: Set<String> = []) {
        http.route("currency-api") { url in
            let text = url.absoluteString
            guard let range = text.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression),
                  let day = CalendarDay(string: String(text[range])) else { return nil }
            if missing.contains(day.description) { return .status(404) }
            return .json(Fixture.fiat(day.description, ["brl": 5 + Double(day.day) / 100, "eur": 0.9]))
        }
    }

    private func makeService(_ http: FakeHTTPClient, _ sandbox: Sandbox) -> HistoryService {
        HistoryService(http: http, cache: sandbox.cache, now: { fixtureNow })
    }

    @Test func fiatWeekUsesDailySnapshots() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        dailyRoutes(http)
        let history = try await makeService(http, sandbox).history(for: CurrencyPair(base: "USD", quote: "BRL"), range: .week)

        #expect(history.points.count == 8)
        #expect(history.points.first?.date == CalendarDay(year: 2026, month: 10, day: 27).date)
        #expect(history.points.last?.date == CalendarDay(year: 2026, month: 11, day: 3).date)
        #expect(approx(history.points.last?.value, 5.03))
        #expect(history.sources == [.currencyAPI])
        #expect(approx(history.change, 5.03 / 5.27 - 1))
        #expect(approx(history.low, 5.01) && approx(history.high, 5.31))
        #expect(http.requests.allSatisfy { request in
            let url = request.url?.absoluteString ?? ""
            return url.contains("currency-api.pages.dev") || url.contains(FakeHTTPClient.exchangeRatesPattern)
        })
    }

    @Test func fiatSeriesEndsWithTheLiveRate() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        dailyRoutes(http)
        http.route(FakeHTTPClient.exchangeRatesPattern, .json(try Fixture.data("coinbase-exchange-rates")))
        let history = try await makeService(http, sandbox).history(for: CurrencyPair(base: "USD", quote: "BRL"), range: .week)

        #expect(history.points.count == 9, "8 daily points + now")
        // Today's 00:00 UTC point is still the daily snapshot; the live rate is appended at "now".
        #expect(approx(history.points.dropLast().last?.value, 5.03))
        #expect(history.points.last?.date == fixtureNow)
        #expect(approx(history.points.last?.value, liveUSDBRL))
        #expect(history.sources == [.coinbase, .currencyAPI])
    }

    @Test func mixedPairUsesLiveFiatForTodaysCandles() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        dailyRoutes(http)
        http.route(FakeHTTPClient.exchangeRatesPattern, .json(try Fixture.data("coinbase-exchange-rates")))
        let yesterday = fixtureNow.addingTimeInterval(-18 * 3600)
        let today = fixtureNow.addingTimeInterval(-3600)
        http.route("BTC-USD/candles", .json(Fixture.candles([(yesterday, 100_000), (today, 100_000)])))
        let history = try await makeService(http, sandbox).history(for: CurrencyPair(base: "BTC", quote: "BRL"), range: .day)

        #expect(history.points.count == 2)
        #expect(approx(history.points.first?.value, 100_000 * 5.02), "yesterday uses the 2026-11-02 snapshot")
        #expect(approx(history.points.last?.value, 100_000 * liveUSDBRL), "today uses the live rate")
    }

    @Test func crossFiatPairAndCaching() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        dailyRoutes(http, missing: ["2026-10-30"])
        let service = makeService(http, sandbox)
        let pair = CurrencyPair(base: "EUR", quote: "BRL")

        let history = try await service.history(for: pair, range: .week)
        #expect(history.points.count == 7, "a missing day is skipped")
        #expect(approx(history.points.last?.value, (1 / 0.9) / (1 / 5.03)))

        let before = http.requests.count
        _ = try await service.history(for: pair, range: .week)
        #expect(http.requests.count == before, "memoized")

        // A new launch reads past days from disk; only today and the missing day hit the network.
        let relaunch = FakeHTTPClient()
        dailyRoutes(relaunch, missing: ["2026-10-30"])
        _ = try await makeService(relaunch, sandbox).history(for: pair, range: .week)
        #expect(relaunch.requests.count == 4, "today + the missing day on both hosts + live rates")
    }

    @Test func quarterSamplesEveryThirdDay() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        dailyRoutes(http)
        let history = try await makeService(http, sandbox).history(for: CurrencyPair(base: "BRL", quote: "USD"), range: .quarter)
        #expect(history.points.count == 31)
        #expect(history.points.first?.date == CalendarDay(year: 2026, month: 8, day: 5).date)
    }

    @Test func fiatDayRangeIsUnavailable() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        await #expect(throws: CurrencyKitError.historyUnavailable) {
            try await makeService(http, sandbox).history(for: CurrencyPair(base: "USD", quote: "BRL"), range: .day)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func cryptoDayUsesFifteenMinuteCandles() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        let candles = (0..<96).map { (time: fixtureNow.addingTimeInterval(Double(-$0) * 900), close: 70_000 + Double($0)) }
        http.route("api.exchange.coinbase.com", .json(Fixture.candles(candles)))
        let history = try await makeService(http, sandbox).history(for: CurrencyPair(base: "BTC", quote: "USD"), range: .day)

        #expect(history.points.count == 96)
        #expect(history.points.last?.value == 70_000)
        #expect(history.points.first?.value == 70_095)
        #expect(history.sources == [.coinbase])
        let url = try #require(http.requests.first?.url?.absoluteString)
        #expect(url.contains("BTC-USD/candles?granularity=900"))
    }

    @Test func cryptoCrossUsesCandlesAndDailyFiat() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        dailyRoutes(http)
        let times = (0..<30).map { fixtureNow.addingTimeInterval(Double(-$0) * 21_600) }
        http.route("BTC-USD/candles", .json(Fixture.candles(times.map { (time: $0, close: 80_000) })))
        let history = try await makeService(http, sandbox).history(for: CurrencyPair(base: "BTC", quote: "BRL"), range: .month)

        #expect(history.points.count == 30)
        #expect(history.sources == [.coinbase, .currencyAPI])
        // Each point uses the BRL rate of its own UTC day.
        for point in history.points {
            let day = CalendarDay(point.date)
            #expect(approx(point.value, 80_000 * (5 + Double(day.day) / 100)))
        }
    }

    @Test func twoCryptoLegsIntersectTimelines() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        let times = (0..<10).map { fixtureNow.addingTimeInterval(Double(-$0) * 3_600) }
        http.route("ETH-USD/candles", .json(Fixture.candles(times.map { (time: $0, close: 2_000) })))
        http.route("BTC-USD/candles", .json(Fixture.candles(times.dropFirst(2).map { (time: $0, close: 80_000) })))
        let history = try await makeService(http, sandbox).history(for: CurrencyPair(base: "ETH", quote: "BTC"), range: .week)
        #expect(history.points.count == 8)
        #expect(history.points.allSatisfy { $0.value == 0.025 })
    }

    @Test func candleFailureSurfaces() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        http.route("api.exchange.coinbase.com", .data(try Fixture.data("coinbase-notfound"), status: 404))
        await #expect(throws: CurrencyKitError.httpStatus(404)) {
            try await makeService(http, sandbox).history(for: CurrencyPair(base: "BTC", quote: "USD"), range: .week)
        }
    }
}
