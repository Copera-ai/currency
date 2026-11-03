@testable import CurrencyKit
import Foundation
import Testing

@MainActor
@Suite("Currency store")
struct CurrencyStoreTests {
    private func makeStore(_ http: FakeHTTPClient, _ sandbox: Sandbox, converterSaveDelay: Duration = .seconds(60)) -> CurrencyStore {
        CurrencyStore(dependencies: CurrencyStore.Dependencies(
            http: http,
            stateStore: sandbox.stateStore,
            cache: sandbox.cache,
            locale: Locale(identifier: "en_US"),
            now: { fixtureNow },
            converterSaveDelay: converterSaveDelay
        ))
    }

    private let usdBRL = CurrencyPair(base: "USD", quote: "BRL")
    private let btcUSD = CurrencyPair(base: "BTC", quote: "USD")

    @Test func refreshPopulatesQuotes() async throws {
        let sandbox = try Sandbox()
        let store = makeStore(try FakeHTTPClient.withFixtures(), sandbox)
        #expect(store.loadState == .idle)
        #expect(store.persistenceOutcome == .seededDefaults)

        await store.refresh()
        #expect(store.loadState == .loaded)
        #expect(store.lastUpdated == fixtureNow)
        #expect(store.lastError == nil)
        #expect(!store.isRefreshing)
        #expect(approx(store.quote(for: usdBRL)?.price, liveUSDBRL))
        #expect(store.quote(for: btcUSD)?.price == 76372.94)
        #expect(Set(store.quotes.keys) == Set(TrackedPair.defaults.map(\.id)))
        #expect(approx(store.converterResult, 100 * liveUSDBRL))
        #expect(store.updatedText(relativeTo: fixtureNow) == "Updated just now")
    }

    @Test func partialFailureIsStale() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        http.route(FakeHTTPClient.productsPattern, .status(500))
        let store = makeStore(http, sandbox)
        await store.refresh()
        #expect(store.loadState == .stale)
        #expect(store.lastError == .httpStatus(500))
        #expect(store.quote(for: btcUSD)?.sources == [.currencyAPI], "BTC still shown from the daily API")
    }

    @Test func offlineWithoutData() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        http.route("", .failure(.notConnectedToInternet))
        let store = makeStore(http, sandbox)
        await store.refresh()
        #expect(store.loadState == .offline)
        #expect(store.snapshot == nil)
        #expect(store.lastError == .offline)
    }

    @Test func serverErrorWithoutDataIsAnError() async throws {
        let sandbox = try Sandbox()
        let http = FakeHTTPClient()
        http.route("", .status(500))
        let store = makeStore(http, sandbox)
        await store.refresh()
        #expect(store.loadState == .error(.httpStatus(500)))
        #expect(store.loadState.isDegraded)
    }

    @Test func offlineKeepsPreviousQuotes() async throws {
        let sandbox = try Sandbox()
        let http = try FakeHTTPClient.withFixtures()
        let store = makeStore(http, sandbox)
        await store.refresh()
        http.route("", .failure(.notConnectedToInternet))
        await store.refresh()
        #expect(store.loadState == .offline)
        #expect(approx(store.quote(for: usdBRL)?.price, liveUSDBRL))
        #expect(store.lastUpdated == fixtureNow)
    }

    // MARK: - Pairs

    @Test func addPairValidation() throws {
        let sandbox = try Sandbox()
        let store = makeStore(FakeHTTPClient(), sandbox)
        let count = store.pairs.count
        #expect(store.addPair(base: "USD", quote: "usd") == .sameCurrency)
        #expect(store.addPair(base: "usd", quote: "brl") == .duplicate)
        #expect(store.addPair(base: "USD", quote: "XYZ") == .unknownCurrency("XYZ"))
        #expect(store.pairs.count == count)

        #expect(store.addPair(base: "gbp", quote: "eur", showInMenuBar: true) == .added)
        #expect(store.pairs.last == TrackedPair(CurrencyPair(base: "GBP", quote: "EUR"), showInMenuBar: true))
        #expect(makeStore(FakeHTTPClient(), sandbox).pairs.last?.id == "GBP/EUR", "persisted")
    }

    @Test func reorderChangesTheArrayAndSticks() throws {
        let sandbox = try Sandbox()
        let store = makeStore(FakeHTTPClient(), sandbox)
        // Move GBP/USD (last) to the top.
        store.movePairs(fromOffsets: IndexSet(integer: 5), toOffset: 0)
        #expect(store.pairs.map(\.id) == ["GBP/USD", "USD/BRL", "EUR/BRL", "BTC/USD", "ETH/USD", "USD/JPY"])
        // Move USD/BRL down past BTC/USD.
        store.movePairs(fromOffsets: IndexSet(integer: 1), toOffset: 4)
        #expect(store.pairs.map(\.id) == ["GBP/USD", "EUR/BRL", "BTC/USD", "USD/BRL", "ETH/USD", "USD/JPY"])

        let reloaded = makeStore(FakeHTTPClient(), sandbox)
        #expect(reloaded.pairs.map(\.id) == store.pairs.map(\.id))
        #expect(reloaded.persistenceOutcome == .loaded)
    }

    @Test func menuBarOrderingOnlyTouchesMenuBarPairs() throws {
        let sandbox = try Sandbox()
        let store = makeStore(FakeHTTPClient(), sandbox)
        store.setShowInMenuBar("USD/JPY", true)
        #expect(store.menuBarPairs.map(\.id) == ["USD/BRL", "BTC/USD", "USD/JPY"])

        store.moveMenuBarPairs(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.menuBarPairs.map(\.id) == ["USD/JPY", "USD/BRL", "BTC/USD"])
        #expect(store.pairs.map(\.id) == ["USD/JPY", "EUR/BRL", "USD/BRL", "ETH/USD", "BTC/USD", "GBP/USD"])
        #expect(makeStore(FakeHTTPClient(), sandbox).menuBarPairs.map(\.id) == ["USD/JPY", "USD/BRL", "BTC/USD"])
    }

    @Test func togglesAndRemovalPersist() throws {
        let sandbox = try Sandbox()
        let store = makeStore(FakeHTTPClient(), sandbox)
        store.toggleFavorite("EUR/BRL")
        store.toggleShowInMenuBar("GBP/USD")
        store.setFavorite("USD/BRL", false)
        store.removePair("ETH/USD")
        store.removePairs(atOffsets: IndexSet(integer: 0))

        let reloaded = makeStore(FakeHTTPClient(), sandbox)
        #expect(reloaded.pairs.map(\.id) == ["EUR/BRL", "BTC/USD", "USD/JPY", "GBP/USD"])
        #expect(reloaded.favoritePairs.map(\.id) == ["EUR/BRL", "BTC/USD"])
        #expect(reloaded.menuBarPairs.map(\.id) == ["BTC/USD", "GBP/USD"])
    }

    // MARK: - Converter and settings

    @Test func converterPersistsAndSwaps() async throws {
        let sandbox = try Sandbox()
        let store = makeStore(try FakeHTTPClient.withFixtures(), sandbox)
        await store.refresh()
        #expect(store.setConverterAmount(text: "1,000 + 250"))
        #expect(!store.setConverterAmount(text: "1++"))
        #expect(store.converter.amount == 1_250)
        store.swapConverterCurrencies()
        #expect(store.converter == ConverterState(from: "BRL", to: "USD", amount: 1_250))
        #expect(approx(store.converterResult, 1_250 / liveUSDBRL))
        #expect(approx(store.convert(1, from: "BTC", to: "BRL"), 76372.94 * liveUSDBRL))

        // Converter edits are coalesced: nothing is written until the delay or stop().
        #expect(makeStore(FakeHTTPClient(), sandbox).converter != store.converter)
        store.stop()
        #expect(makeStore(FakeHTTPClient(), sandbox).converter == store.converter)
    }

    @Test func converterSavesAreCoalesced() async throws {
        let sandbox = try Sandbox()
        let store = makeStore(FakeHTTPClient(), sandbox, converterSaveDelay: .milliseconds(50))
        for text in ["1", "12", "123"] { #expect(store.setConverterAmount(text: text)) }
        #expect(makeStore(FakeHTTPClient(), sandbox).converter.amount != 123)
        try await Task.sleep(for: .milliseconds(400))
        #expect(makeStore(FakeHTTPClient(), sandbox).converter.amount == 123)
    }

    @Test func blankAmountIsZero() throws {
        let sandbox = try Sandbox()
        let store = makeStore(FakeHTTPClient(), sandbox)
        #expect(store.setConverterAmount(text: "250"))
        #expect(store.setConverterAmount(text: "  "))
        #expect(store.converter.amount == 0)
        #expect(!store.setConverterAmount(text: "abc"))
        #expect(store.converter.amount == 0)
    }

    @Test func settingsPersistAndRebuildFormatter() throws {
        let sandbox = try Sandbox()
        let store = makeStore(FakeHTTPClient(), sandbox)
        store.settings.decimals = .precise
        store.settings.refreshInterval = .oneMinute
        #expect(store.formatter.decimals == .precise)
        let reloaded = makeStore(FakeHTTPClient(), sandbox)
        #expect(reloaded.settings.refreshInterval == .oneMinute)
        #expect(reloaded.formatter.decimals == .precise)
    }

    @Test func menuBarLabels() async throws {
        let sandbox = try Sandbox()
        let store = makeStore(try FakeHTTPClient.withFixtures(), sandbox)
        await store.refresh()

        #expect(store.menuBarLabel(for: usdBRL).text == "USD/BRL 5.50 ▲")
        #expect(store.menuBarLabel(for: btcUSD).text == "BTC/USD 76,372.94 ▼")
        store.settings.menuBarLabelFormat = .symbol
        #expect(store.menuBarLabel(for: usdBRL).text == "R$ 5.50 ▲")
        store.settings.menuBarLabelFormat = .flag
        store.settings.showChangeArrow = false
        #expect(store.menuBarLabel(for: usdBRL).text == "🇺🇸 5.50")
        #expect(store.menuBarLabel(for: btcUSD).text == "₿ 76,372.94")
        store.settings.menuBarLabelFormat = .value
        #expect(store.menuBarLabel(for: CurrencyPair(base: "USD", quote: "XYZ")).text == "—")
    }

    @Test func historyPassThrough() async throws {
        let sandbox = try Sandbox()
        let store = makeStore(FakeHTTPClient(), sandbox)
        #expect(store.defaultRange(for: usdBRL) == .week)
        #expect(store.availableRanges(for: btcUSD).first == .day)
        await #expect(throws: CurrencyKitError.historyUnavailable) { try await store.history(for: usdBRL, range: .day) }
    }

    @Test func arrayMoveMatchesOnMoveSemantics() {
        var items = ["a", "b", "c", "d", "e"]
        items.move(fromOffsets: IndexSet([1, 3]), toOffset: 5)
        #expect(items == ["a", "c", "e", "b", "d"])
        items.move(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        #expect(items == ["d", "a", "c", "e", "b"])
        items.move(fromOffsets: IndexSet(integer: 2), toOffset: 2)
        #expect(items == ["d", "a", "c", "e", "b"])
    }
}
