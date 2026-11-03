import Foundation
import os

/// Every currency the app knows: ~150 fiat currencies plus curated crypto assets.
///
/// Fiat entries come from a bundled snapshot of the currency API's
/// `currencies.json` (filtered to current ISO 4217 codes); regenerate it with
/// `Scripts/generate-fiat-catalog.swift`.
public struct CurrencyCatalog: Sendable {
    /// Fiat currencies sorted by code.
    public let fiat: [Currency]
    /// Crypto assets, roughly by market cap.
    public let crypto: [Currency]
    private let byCode: [String: Currency]

    /// The bundled catalog.
    public static let shared = CurrencyCatalog(fiat: loadBundledFiat(), crypto: CryptoAssets.all)

    public init(fiat: [Currency], crypto: [Currency]) {
        self.fiat = fiat
        self.crypto = crypto
        var byCode: [String: Currency] = [:]
        for currency in fiat + crypto where byCode[currency.code] == nil {
            byCode[currency.code] = currency
        }
        self.byCode = byCode
    }

    /// Fiat followed by crypto.
    public var all: [Currency] { fiat + crypto }

    /// Looks up a currency by code (case-insensitive).
    public func currency(for code: String) -> Currency? {
        byCode[code.uppercased()]
    }

    public subscript(code: String) -> Currency? { currency(for: code) }

    /// Whether `code` is known.
    public func contains(_ code: String) -> Bool { byCode[code.uppercased()] != nil }

    /// Coinbase products for every crypto asset listed there.
    public var coinbaseProductIDs: [String] { crypto.compactMap(\.coinbaseProductID) }

    /// Currencies whose code or name contains `query` (case/diacritic-insensitive).
    /// Exact code matches come first. An empty query returns ``all``.
    public func search(_ query: String) -> [Currency] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }
        let matches = all.filter {
            $0.code.localizedStandardContains(needle) || $0.name.localizedStandardContains(needle)
        }
        let isExact: (Currency) -> Bool = { $0.code.caseInsensitiveCompare(needle) == .orderedSame }
        return matches.filter(isExact) + matches.filter { !isExact($0) }
    }

    /// Ranges a chart can show for `pair`. 24H needs at least one live (Coinbase) leg.
    public func availableRanges(for pair: CurrencyPair) -> [HistoryRange] {
        hasLiveLeg(pair) ? HistoryRange.allCases : [.week, .month, .quarter]
    }

    /// The range a chart should open with: 24H for crypto pairs, 7D otherwise.
    public func defaultRange(for pair: CurrencyPair) -> HistoryRange {
        hasLiveLeg(pair) ? .day : .week
    }

    func hasLiveLeg(_ pair: CurrencyPair) -> Bool {
        currency(for: pair.base)?.coinbaseProductID != nil || currency(for: pair.quote)?.coinbaseProductID != nil
    }

    // MARK: - Bundled data

    private struct Entry: Decodable {
        let code: String
        let name: String
        let symbol: String
    }

    static func loadBundledFiat() -> [Currency] {
        guard let url = Bundle.module.url(forResource: "fiat-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            Log.catalog.fault("Bundled fiat catalog is missing or unreadable")
            return [Currency(code: "USD", name: "US Dollar", symbol: "$", kind: .fiat, flag: "🇺🇸")]
        }
        return entries.map {
            Currency(code: $0.code, name: $0.name, symbol: $0.symbol, kind: .fiat, flag: CurrencyFlags.flag(forCurrencyCode: $0.code))
        }
    }
}
