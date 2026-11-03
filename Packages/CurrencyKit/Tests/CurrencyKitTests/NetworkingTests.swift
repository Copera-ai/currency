@testable import CurrencyKit
import Foundation
import Testing

@Suite("Fiat and Coinbase services")
struct NetworkingTests {
    @Test func latestUsesPrimaryHostAndBypassesCache() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        let service = FiatRatesService(http: http, cache: sandbox.cache, now: { fixtureNow })

        let latest = try await service.latest()
        #expect(latest.day.description == "2026-11-03")
        let request = try #require(http.requests.first)
        #expect(request.url == Endpoints.fiatLatest(.pages))
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(http.requests.count == 1)
    }

    @Test(arguments: [FakeHTTPClient.Reply.status(503), .json(Data("oops".utf8)), .failure(.cannotConnectToHost)])
    func latestFallsBackToJsDelivr(primary: FakeHTTPClient.Reply) async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        http.route(FakeHTTPClient.latestPattern, primary)
        let service = FiatRatesService(http: http, cache: sandbox.cache, now: { fixtureNow })

        let latest = try await service.latest()
        #expect(latest.day.description == "2026-11-02", "the jsDelivr fixture lags a day")
        #expect(http.requests.map(\.url) == [Endpoints.fiatLatest(.pages), Endpoints.fiatLatest(.jsdelivr)])
    }

    @Test func allHostsOfflineReportsOffline() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        http.route("usd.min.json", .failure(.notConnectedToInternet))
        let service = FiatRatesService(http: http, cache: sandbox.cache, now: { fixtureNow })
        await #expect(throws: CurrencyKitError.offline) { try await service.latest() }
    }

    @Test func allHostsFailingReportsLastError() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        http.route("usd.min.json", .status(500))
        let service = FiatRatesService(http: http, cache: sandbox.cache, now: { fixtureNow })
        await #expect(throws: CurrencyKitError.httpStatus(500)) { try await service.latest() }
        #expect(http.requests.count == 2)
    }

    @Test func datedSnapshotsAreCachedOnDiskForever() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        let day = try #require(CalendarDay(string: "2026-11-02"))

        let first = try await FiatRatesService(http: http, cache: sandbox.cache, now: { fixtureNow }).snapshot(for: day)
        #expect(http.requests.first?.url == Endpoints.fiatSnapshot(day, .pages))
        #expect(sandbox.files(in: "Caches").contains("fiat-usd-2026-11-02.json"))

        // A fresh service (new launch) with a dead network still has it.
        let offline = FakeHTTPClient()
        offline.route("", .failure(.notConnectedToInternet))
        let second = try await FiatRatesService(http: offline, cache: sandbox.cache, now: { fixtureNow }).snapshot(for: day)
        #expect(second == first)
        #expect(offline.requests.isEmpty)
    }

    @Test func todaysSnapshotIsNotCachedOnDisk() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        http.route("2026-11-03.currency-api", .json(try Fixture.data("fiat-latest")))
        let service = FiatRatesService(http: http, cache: sandbox.cache, now: { fixtureNow })
        _ = try await service.snapshot(for: CalendarDay(fixtureNow))
        #expect(sandbox.files(in: "Caches").isEmpty)
    }

    @Test func datedSnapshotWithWrongDateIsRejected() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        http.route("currency-api", .json(Fixture.fiat("2026-10-01", ["brl": 5])))
        let service = FiatRatesService(http: http, cache: sandbox.cache, now: { fixtureNow })
        await #expect(throws: CurrencyKitError.self) { try await service.snapshot(for: CalendarDay(year: 2026, month: 10, day: 2)) }
        #expect(sandbox.files(in: "Caches").isEmpty)
    }

    @Test func daysBeforeTheArchiveAreUnavailable() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        let service = FiatRatesService(http: http, cache: sandbox.cache, now: { fixtureNow })
        await #expect(throws: CurrencyKitError.historyUnavailable) {
            try await service.snapshot(for: CalendarDay(year: 2024, month: 3, day: 1))
        }
        #expect(http.requests.isEmpty)
    }

    @Test func coinbaseBatchesAllProductsInOneRequest() async throws {
        let http = try FakeHTTPClient.withFixtures()
        let tickers = try await CoinbaseService(http: http).tickers(["BTC-USD", "ETH-USD", "SOL-USD", "XYZ-USD"])
        #expect(Set(tickers.keys) == ["BTC", "ETH", "SOL"], "unknown products are just absent")
        #expect(http.requests.count == 1)
        let query = try #require(http.requests.first?.url?.query())
        #expect(query == "product_ids=BTC-USD&product_ids=ETH-USD&product_ids=SOL-USD&product_ids=XYZ-USD")
        #expect(http.requests.first?.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func coinbaseRejectedBatchFallsBackPerProduct() async throws {
        let http = FakeHTTPClient()
        let fixture = try Fixture.data("coinbase-products")
        http.route(FakeHTTPClient.productsPattern) { url in
            let ids = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.compactMap(\.value) ?? []
            if ids.count > 1 { return .status(400) }
            if ids == ["ETH-USD"] { return .status(500) }
            let filtered = (try? CoinbaseTicker.decodeList(fixture))?.first { $0.productID == ids.first }
            guard let ticker = filtered else { return .json(Data(#"{"products":[]}"#.utf8)) }
            return .json(Data(#"{"products":[{"product_id":"\#(ticker.productID)","price":"\#(ticker.price)","price_percentage_change_24h":"1"}]}"#.utf8))
        }
        let tickers = try await CoinbaseService(http: http).tickers(["BTC-USD", "ETH-USD", "SOL-USD"])
        #expect(Set(tickers.keys) == ["BTC", "SOL"], "one failing coin doesn't drop the others")
        #expect(http.requests.count == 4)
    }

    @Test func coinbaseRateLimitIsNotRetriedPerProduct() async throws {
        let http = FakeHTTPClient()
        http.route(FakeHTTPClient.productsPattern, .status(429))
        await #expect(throws: CurrencyKitError.httpStatus(429)) { try await CoinbaseService(http: http).tickers(["BTC-USD", "ETH-USD"]) }
        #expect(http.requests.count == 1)
    }

    @Test func candleRequestShape() async throws {
        let http = FakeHTTPClient()
        http.route("api.exchange.coinbase.com", .json(try Fixture.data("coinbase-candles-hourly")))
        let end = fixtureNow
        let candles = try await CoinbaseService(http: http).candles(
            productID: "BTC-USD", granularity: 3_600, start: end.addingTimeInterval(-86_400), end: end
        )
        #expect(!candles.isEmpty)
        let url = try #require(http.requests.first?.url?.absoluteString)
        #expect(url == "https://api.exchange.coinbase.com/products/BTC-USD/candles?granularity=3600&start=2026-11-02T12:00:00Z&end=2026-11-03T12:00:00Z")
    }

    @Test func errorMapping() {
        #expect(CurrencyKitError(URLError(.notConnectedToInternet)) == .offline)
        #expect(CurrencyKitError(URLError(.timedOut)) == .timedOut)
        #expect(CurrencyKitError(URLError(.badServerResponse)) == .transport("URLError -1011"))
        #expect(CurrencyKitError(CurrencyKitError.noData) == .noData)
        #expect(CurrencyKitError.offline.isConnectivity)
        #expect(!CurrencyKitError.httpStatus(500).isConnectivity)
    }
}
