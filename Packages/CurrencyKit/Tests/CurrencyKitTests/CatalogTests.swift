@testable import CurrencyKit
import Foundation
import Testing

@Suite("Currency catalog")
struct CatalogTests {
    let catalog = CurrencyCatalog.shared

    @Test func bundledFiatCatalogLoads() throws {
        #expect(catalog.fiat.count >= 150)
        #expect(Set(catalog.all.map(\.code)).count == catalog.all.count, "codes are unique")
        let brl = try #require(catalog["brl"])
        #expect(brl.name == "Brazilian Real")
        #expect(brl.symbol == "R$")
        #expect(brl.kind == .fiat)
        #expect(catalog["USD"]?.symbol == "$")
        #expect(catalog["EUR"]?.symbol == "€")
        #expect(catalog["XAU"] == nil, "metals are not currencies")
    }

    @Test func fiatNamesMatchCurrencyAPI() throws {
        let names = try JSONDecoder().decode([String: String].self, from: try Fixture.data("currencies"))
        for code in ["USD", "BRL", "JPY", "GBP", "EUR"] {
            #expect(catalog[code]?.name == names[code.lowercased()])
        }
    }

    @Test func everyCatalogCodeHasALiveRate() throws {
        let latest = try FiatSnapshot.decode(try Fixture.data("fiat-latest"))
        let missing = catalog.all.map(\.code).filter { latest.unitsPerUSD[$0] == nil }
        #expect(missing.isEmpty, "no rate for \(missing)")
    }

    @Test(arguments: [("USD", "🇺🇸"), ("BRL", "🇧🇷"), ("EUR", "🇪🇺"), ("JPY", "🇯🇵"), ("GBP", "🇬🇧"), ("CHF", "🇨🇭"), ("XPF", "🇵🇫")])
    func flags(code: String, flag: String) {
        #expect(CurrencyFlags.flag(forCurrencyCode: code) == flag)
        #expect(catalog[code]?.flag == flag)
    }

    @Test func noFlagWithoutARegion() {
        #expect(CurrencyFlags.flag(forCurrencyCode: "BTC") == nil)
        #expect(CurrencyFlags.flag(forCurrencyCode: "XDR") == nil)
        #expect(CurrencyFlags.flag(forRegion: "B1") == nil)
    }

    @Test func cryptoAssets() throws {
        let btc = try #require(catalog["BTC"])
        #expect(btc.kind == .crypto)
        #expect(btc.flag == nil)
        #expect(btc.badge == "₿")
        #expect(btc.brandColorHex == "#F7931A")
        #expect(btc.coinbaseProductID == "BTC-USD")
        #expect(catalog["USDC"]?.coinbaseProductID == nil, "no USDC-USD product on Coinbase")
        #expect(catalog.crypto.allSatisfy { $0.brandColorHex?.count == 7 })
        #expect(catalog.coinbaseProductIDs.contains("SOL-USD"))
    }

    @Test func search() {
        #expect(catalog.search("btc").first?.code == "BTC")
        #expect(catalog.search("real").contains { $0.code == "BRL" })
        #expect(catalog.search("yen").first?.code == "JPY")
        #expect(catalog.search("  ").count == catalog.all.count)
    }

    @Test func historyRangesPerPair() {
        let fiat = CurrencyPair(base: "USD", quote: "BRL")
        let crypto = CurrencyPair(base: "BRL", quote: "ETH")
        let stablecoin = CurrencyPair(base: "USDC", quote: "EUR")
        #expect(catalog.availableRanges(for: fiat) == [.week, .month, .quarter])
        #expect(catalog.defaultRange(for: fiat) == .week)
        #expect(catalog.availableRanges(for: crypto) == HistoryRange.allCases)
        #expect(catalog.defaultRange(for: crypto) == .day)
        #expect(catalog.defaultRange(for: stablecoin) == .week)
    }

    @Test func defaultPairsAreValid() {
        #expect(TrackedPair.defaults.map(\.id) == ["USD/BRL", "EUR/BRL", "BTC/USD", "ETH/USD", "USD/JPY", "GBP/USD"])
        #expect(TrackedPair.defaults.allSatisfy { catalog.contains($0.pair.base) && catalog.contains($0.pair.quote) })
        #expect(TrackedPair.defaults.contains { $0.showInMenuBar })
    }
}
