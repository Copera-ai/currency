@testable import CurrencyKit
import Foundation
import Synchronization
import Testing

@Suite("Rates engine")
struct RatesEngineTests {
    /// A clock the test can move.
    final class TestClock: Sendable {
        private let value = Mutex(fixtureNow)
        var now: Date { value.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { value.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    private func makeEngine(_ http: FakeHTTPClient, _ sandbox: Sandbox, clock: TestClock = TestClock()) -> RatesEngine {
        RatesEngine(http: http, cache: sandbox.cache, now: { clock.now })
    }

    @Test func mergesLiveFiatDailyFallbackAndCoinbaseCrypto() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        let snapshot = try await makeEngine(http, sandbox).refresh()

        #expect(snapshot.isComplete)
        #expect(snapshot.fiatDay?.description == "2026-11-03")
        #expect(snapshot.rates["USD"]?.usdPerUnit == 1)

        // USD/BRL is live (5.499); its change is measured against today's 00:00 UTC
        // daily snapshot (5.44059239).
        let usdBRL = try #require(snapshot.quote(for: CurrencyPair(base: "USD", quote: "BRL")))
        #expect(approx(usdBRL.price, liveUSDBRL))
        #expect(approx(usdBRL.change24h, liveUSDBRL / 5.44059239 - 1))
        #expect(usdBRL.asOf == fixtureNow)
        #expect(usdBRL.sources == [.coinbase])

        // Fiat missing from the live feed falls back to the daily API with its
        // day-over-day change (CHF: 0.81806472 today vs 0.82318814 yesterday).
        let chf = try #require(snapshot.rates["CHF"])
        #expect(chf.source == .currencyAPI)
        #expect(chf.usdPerUnit == 1 / 0.81806472)
        #expect(approx(chf.change24h, (1 / 0.81806472) / (1 / 0.82318814) - 1))
        #expect(chf.asOf == CalendarDay(year: 2026, month: 11, day: 3).date)

        // BTC comes from Coinbase with its own 24h change.
        let btc = try #require(snapshot.rates["BTC"])
        #expect(btc.source == .coinbase)
        #expect(btc.usdPerUnit == 76372.94)
        #expect(approx(btc.change24h, -0.021701707235811))
        #expect(btc.asOf == fixtureNow)

        // Crypto not served by Coinbase falls back to the daily API.
        #expect(snapshot.rates["USDC"]?.source == .currencyAPI)
        #expect(snapshot.rates["ADA"]?.source == .currencyAPI, "not in the products fixture")

        // Persisted for the next launch.
        let restored = await makeEngine(FakeHTTPClient(), sandbox).restoreFromDisk()
        #expect(restored?.rates["BTC"]?.usdPerUnit == 76372.94)
        #expect(restored?.issues.isEmpty == true)
    }

    @Test func concurrentRefreshesShareOneFetch() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures(latency: .milliseconds(100))
        let engine = makeEngine(http, sandbox)

        let snapshots = try await withThrowingTaskGroup(of: RatesSnapshot.self) { group in
            for index in 0..<8 { group.addTask { try await engine.refresh(force: index.isMultiple(of: 2)) } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(snapshots.count == 8)
        #expect(Set(snapshots).count == 1)
        #expect(http.requestCount(FakeHTTPClient.latestPattern) == 1)
        #expect(http.requestCount(FakeHTTPClient.previousDayPattern) == 1)
        #expect(http.requestCount(FakeHTTPClient.productsPattern) == 1)
        #expect(http.requestCount(FakeHTTPClient.exchangeRatesPattern) == 1)
    }

    @Test func perSourceTTLs() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        let clock = TestClock()
        let engine = makeEngine(http, sandbox, clock: clock)

        _ = try await engine.refresh()
        clock.advance(5)
        _ = try await engine.refresh()
        #expect(http.requests.count == 4, "all sources fresh")

        clock.advance(10) // past the 10s live TTLs, inside the 10 min daily TTL
        _ = try await engine.refresh()
        #expect(http.requestCount(FakeHTTPClient.productsPattern) == 2)
        #expect(http.requestCount(FakeHTTPClient.exchangeRatesPattern) == 2)
        #expect(http.requestCount(FakeHTTPClient.latestPattern) == 1)

        _ = try await engine.refresh(force: true)
        #expect(http.requestCount(FakeHTTPClient.latestPattern) == 2)
        #expect(http.requestCount(FakeHTTPClient.previousDayPattern) == 1, "previous day reused")
    }

    @Test func failingSourceKeepsOthersAndBacksOff() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        http.route(FakeHTTPClient.productsPattern, .status(503))
        let clock = TestClock()
        let engine = makeEngine(http, sandbox, clock: clock)

        let snapshot = try await engine.refresh()
        #expect(snapshot.issues == [.crypto: .httpStatus(503)])
        #expect(snapshot.rates["BRL"] != nil)
        #expect(snapshot.rates["BTC"]?.source == .currencyAPI, "BTC degrades to the daily rate")

        let health = await engine.sourceHealth(.crypto)
        #expect(health.consecutiveFailures == 1)
        #expect(health.retryAt == fixtureNow.addingTimeInterval(30))

        clock.advance(25) // TTL passed but still inside the 30s backoff
        let during = try await engine.refresh()
        #expect(http.requestCount(FakeHTTPClient.productsPattern) == 1)
        #expect(during.issues[.crypto] == .httpStatus(503), "issue persists while backing off")

        clock.advance(10)
        _ = try await engine.refresh()
        #expect(http.requestCount(FakeHTTPClient.productsPattern) == 2)
        #expect(await engine.sourceHealth(.crypto).retryAt == clock.now.addingTimeInterval(60), "doubled")

        http.route(FakeHTTPClient.productsPattern, .json(try Fixture.data("coinbase-products")))
        let recovered = try await engine.refresh(force: true)
        #expect(recovered.isComplete)
        #expect(recovered.rates["BTC"]?.source == .coinbase)
        #expect(await engine.sourceHealth(.crypto).consecutiveFailures == 0)
    }

    @Test func backoffDelayIsExponentialAndCapped() {
        let configuration = RatesEngine.Configuration(backoffBase: 30, backoffMax: 900)
        let delays = (1...7).map { RatesEngine.backoffDelay(failures: $0, configuration: configuration) }
        #expect(delays == [30, 60, 120, 240, 480, 900, 900])
        #expect(RatesEngine.backoffDelay(failures: 0, configuration: configuration) == 0)
    }

    @Test func missingPreviousDayLeavesDailyOnlyChangeUnknown() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        http.route("2026-11-02", .status(404))
        let snapshot = try await makeEngine(http, sandbox).refresh()
        #expect(snapshot.isComplete)
        #expect(snapshot.rates["CHF"]?.change24h == nil)
        #expect(snapshot.quote(for: CurrencyPair(base: "USD", quote: "CHF"))?.change24h == nil)
        #expect(snapshot.rates["BRL"]?.change24h != nil, "live change only needs today's snapshot")
    }

    @Test func liveFiatFailureFallsBackToDailyRates() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        http.route(FakeHTTPClient.exchangeRatesPattern, .status(503))
        let snapshot = try await makeEngine(http, sandbox).refresh()

        #expect(snapshot.issues == [.liveFiat: .httpStatus(503)])
        let usdBRL = try #require(snapshot.quote(for: CurrencyPair(base: "USD", quote: "BRL")))
        #expect(usdBRL.price == 5.44059239)
        #expect(approx(usdBRL.change24h, 5.44059239 / 5.43870352 - 1))
        #expect(usdBRL.sources == [.currencyAPI])
    }

    @Test func liveFeedOnlyOverridesFiat() async throws {
        let sandbox = try Sandbox()
        let snapshot = try await makeEngine(try FakeHTTPClient.withFixtures(), sandbox).refresh()
        // The live feed also lists BTC and USDC; crypto keeps its own sources.
        #expect(snapshot.rates["BTC"]?.usdPerUnit == 76372.94)
        #expect(snapshot.rates["USDC"]?.source == .currencyAPI)
        #expect(snapshot.rates["EUR"]?.source == .coinbase)
    }

    @Test func restoredLiveRatesBeatOlderDailyRates() async throws {
        let sandbox = try Sandbox()
        _ = try await makeEngine(try FakeHTTPClient.withFixtures(), sandbox).refresh()

        let http = try FakeHTTPClient.withFixtures()
        http.route(FakeHTTPClient.exchangeRatesPattern, .failure(.timedOut))
        let engine = makeEngine(http, sandbox)
        _ = await engine.restoreFromDisk()
        let snapshot = try await engine.refresh(force: true)
        #expect(snapshot.issues[.liveFiat] != nil)
        #expect(snapshot.rates["BRL"]?.source == .coinbase, "the 12:00 live value is newer than the 00:00 daily one")
        #expect(approx(snapshot.quote(for: CurrencyPair(base: "USD", quote: "BRL"))?.price, liveUSDBRL))
    }

    @Test func totalFailureWithoutDataThrows() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        http.route("", .failure(.notConnectedToInternet))
        await #expect(throws: CurrencyKitError.offline) { try await makeEngine(http, sandbox).refresh() }
    }

    @Test func totalFailureWithRestoredDataServesIt() async throws {
        let sandbox = try Sandbox()
        _ = try await makeEngine(try FakeHTTPClient.withFixtures(), sandbox).refresh()

        let offline = FakeHTTPClient()
        offline.route("", .failure(.notConnectedToInternet))
        let engine = makeEngine(offline, sandbox)
        let restored = try #require(await engine.restoreFromDisk())
        let snapshot = try await engine.refresh(force: true)
        #expect(snapshot.issues == [.fiat: .offline, .liveFiat: .offline, .crypto: .offline])
        #expect(snapshot.rates["BRL"]?.usdPerUnit == restored.rates["BRL"]?.usdPerUnit)
        #expect(snapshot.fetchedAt == restored.fetchedAt, "fetchedAt reflects the last real fetch")
    }
}
