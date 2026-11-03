@testable import CurrencyKit
import Foundation
import Testing

@Suite("Persistence")
struct PersistenceTests {
    /// A throwaway `UserDefaults` suite.
    final class LegacySuite {
        let name = "CurrencyKitTests.\(UUID().uuidString)"
        var defaults: UserDefaults { UserDefaults(suiteName: name) ?? .standard }
        deinit { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    }

    @Test func firstLaunchSeedsDefaultsAndWritesFile() throws {
        let sandbox = try Sandbox()
        let store = sandbox.stateStore
        let (state, outcome) = store.load()
        #expect(outcome == .seededDefaults)
        #expect(state == .initial)
        #expect(state.pairs == TrackedPair.defaults)
        #expect(state.settings.refreshInterval == .fiveMinutes)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(store.load().outcome == .loaded)
    }

    @Test func roundTrip() throws {
        let sandbox = try Sandbox()
        let store = sandbox.stateStore
        var state = PersistedState.initial
        state.pairs = [TrackedPair(CurrencyPair(base: "gbp", quote: "eur"), isFavorite: true, showInMenuBar: true)]
        state.settings.refreshInterval = .oneHour
        state.settings.menuBarLabelFormat = .flag
        state.settings.decimals = .precise
        state.converter = ConverterState(from: "BTC", to: "JPY", amount: 0.5)
        try store.save(state)

        let (loaded, outcome) = store.load()
        #expect(outcome == .loaded)
        #expect(loaded == state)
        #expect(loaded.pairs.first?.id == "GBP/EUR")

        let json = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(json.contains("\"schemaVersion\" : 1"))
    }

    @Test func corruptFileIsBackedUpNotOverwritten() throws {
        let sandbox = try Sandbox()
        let store = sandbox.stateStore
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let garbage = Data("{\"schemaVersion\":1,\"pairs\":[{\"pair\":".utf8)
        try garbage.write(to: store.fileURL)

        let (state, outcome) = store.load()
        #expect(state == .initial)
        guard case .recoveredFromCorruptFile(let backup?) = outcome else {
            Issue.record("Unexpected outcome \(outcome)")
            return
        }
        #expect(try Data(contentsOf: backup) == garbage, "original bytes preserved")
        #expect(backup.lastPathComponent.hasPrefix("state.corrupt-"))
        #expect(store.load().outcome == .loaded, "a fresh file replaced it")
    }

    @Test func newerSchemaIsBackedUp() throws {
        let sandbox = try Sandbox()
        let store = sandbox.stateStore
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":99,"somethingNew":true}"#.utf8).write(to: store.fileURL)
        guard case .recoveredFromCorruptFile(let backup?) = store.load().outcome else {
            Issue.record("Expected recovery")
            return
        }
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test func settingsTolerateMissingAndUnknownValues() throws {
        let json = #"{"refreshInterval":900,"menuBarLabelFormat":"bogus"}"#
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data(json.utf8))
        #expect(settings.refreshInterval == .fifteenMinutes)
        #expect(settings.menuBarLabelFormat == .pair)
        #expect(settings.showChangeArrow)
        #expect(settings.decimals == .automatic)
    }

    @Test func retiredGreenAccentDecodesAsEmerald() throws {
        let decode = { (accent: String) in
            try JSONDecoder().decode(UserSettings.self, from: Data(#"{"accent":"\#(accent)"}"#.utf8)).accent
        }
        #expect(try decode("green") == .emerald)
        #expect(try decode("pink") == .pink)
        #expect(try decode("bogus") == .emerald)
        let encoded = try JSONEncoder().encode(UserSettings())
        #expect(try JSONDecoder().decode(UserSettings.self, from: encoded).accent == .emerald)
    }

    @Test func duplicatePairsInFileAreDropped() throws {
        let sandbox = try Sandbox()
        let store = sandbox.stateStore
        var state = PersistedState.initial
        let pair = TrackedPair(CurrencyPair(base: "USD", quote: "BRL"))
        state.pairs = [pair, pair, TrackedPair(CurrencyPair(base: "USD", quote: "USD"))]
        try store.save(state)
        #expect(store.load().state.pairs == [pair])
    }

    @Test func migratesLegacyUserDefaults() throws {
        let sandbox = try Sandbox()
        let suite = LegacySuite()
        let legacyPairs = #"""
        [{"id":1,"base":"USD","quote":"BRL","isFavorite":false,"isTracked":true,"sortOrder":3},
         {"id":2,"base":"BTC","quote":"USD","isFavorite":true,"isTracked":true,"sortOrder":2},
         {"id":3,"base":"EUR","quote":"BRL","isFavorite":false,"isTracked":false,"sortOrder":1},
         {"id":4,"base":"EUR","quote":"BRL","isFavorite":false,"isTracked":true,"sortOrder":9}]
        """#
        let defaults = suite.defaults
        defaults.set(Data(legacyPairs.utf8), forKey: "com.copera.currency.pairs")
        defaults.set(10_800, forKey: "com.copera.currency.refreshInterval")
        defaults.set("plain", forKey: "com.copera.currency.menuBarFormat")
        defaults.set(false, forKey: "com.copera.currency.showChangeInMenuBar")
        defaults.set("dark", forKey: "com.copera.currency.appearance")
        defaults.set("green", forKey: "com.copera.currency.accent")
        defaults.set(true, forKey: "com.copera.currency.reduceTransparency")

        let store = StateStore(directory: sandbox.path("Support"), legacySuiteName: suite.name)
        let (state, outcome) = store.load()
        #expect(outcome == .migratedFromLegacy)
        // Old visible order: favorites first, then sortOrder. Duplicates collapse.
        #expect(state.pairs.map(\.id) == ["BTC/USD", "EUR/BRL", "USD/BRL"])
        #expect(state.pairs[0].isFavorite && state.pairs[0].showInMenuBar)
        #expect(!state.pairs[1].showInMenuBar, "isTracked == false → hidden from menu bar, but kept")
        #expect(state.settings.refreshInterval == .oneHour, "3h is no longer offered")
        #expect(state.settings.menuBarLabelFormat == .value)
        #expect(!state.settings.showChangeArrow)
        #expect(state.settings.appearance == .dark)
        #expect(state.settings.accent == .emerald, "retired \"green\" maps to emerald")
        #expect(state.settings.reduceTransparency)

        // One-time: the file now exists and wins over the legacy keys.
        defaults.set("pair", forKey: "com.copera.currency.menuBarFormat")
        let again = store.load()
        #expect(again.outcome == .loaded)
        #expect(again.state.settings.menuBarLabelFormat == .value)
    }

    @Test func legacySettingsWithoutPairsKeepDefaultPairs() throws {
        let sandbox = try Sandbox()
        let suite = LegacySuite()
        suite.defaults.set("symbol", forKey: "com.copera.currency.menuBarFormat")
        let (state, outcome) = StateStore(directory: sandbox.path("Support"), legacySuiteName: suite.name).load()
        #expect(outcome == .migratedFromLegacy)
        #expect(state.pairs == TrackedPair.defaults)
        #expect(state.settings.menuBarLabelFormat == .symbol)
    }

    @Test func emptyLegacySuiteSeedsDefaults() throws {
        let sandbox = try Sandbox()
        let suite = LegacySuite()
        #expect(StateStore(directory: sandbox.path("Support"), legacySuiteName: suite.name).load().outcome == .seededDefaults)
    }

    @Test func lastRatesCacheRoundTrip() throws {
        let sandbox = try Sandbox()
        #expect(sandbox.cache.loadLastRates() == nil)
        let snapshot = RatesSnapshot(
            rates: ["BRL": AssetRate(usdPerUnit: 0.1845, change24h: -0.0031, asOf: fixtureNow, source: .currencyAPI)],
            fetchedAt: fixtureNow,
            fiatDay: CalendarDay(fixtureNow),
            issues: [.crypto: .offline]
        )
        sandbox.cache.saveLastRates(snapshot)
        let loaded = try #require(sandbox.cache.loadLastRates())
        #expect(loaded.rates == snapshot.rates)
        #expect(loaded.fiatDay == snapshot.fiatDay)
        #expect(loaded.issues.isEmpty, "issues are transient")
    }
}
