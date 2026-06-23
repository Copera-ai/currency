import Foundation

/// Whether a currency is a traditional fiat currency or a cryptocurrency.
///
/// Used to drive badge rendering: crypto currencies carry a coloured badge
/// (see ``Currency/badgeHex``) while fiat currencies do not.
enum CurrencyKind: String, Codable, Hashable, Sendable {
    case fiat
    case crypto
}

/// A single supported currency in the catalog.
///
/// The catalog is static (see ``Currency/supported``); live exchange rates are
/// supplied separately by the networking layer and stored as ``NormalizedRate``.
struct Currency: Codable, Hashable, Sendable {
    /// Uppercase ISO-style code, e.g. `"USD"`, `"BTC"`.
    let code: String
    /// Display symbol, e.g. `"$"`, `"₿"`.
    let symbol: String
    /// Human-readable name, e.g. `"US Dollar"`.
    let name: String
    /// Fiat vs. crypto classification.
    let kind: CurrencyKind
    /// Hex badge colour (e.g. `"#f7931a"`). Non-nil ONLY for crypto currencies.
    let badgeHex: String?
}

/// A user-tracked conversion pair (base → quote).
struct CurrencyPair: Codable, Hashable, Sendable, Identifiable {
    /// Stable identity; also the initial sort order for the seed pairs.
    let id: Int
    /// Base currency code (the "from" side).
    var base: String
    /// Quote currency code (the "to" side).
    var quote: String
    /// Whether the user has favourited this pair (favourites sort first).
    var isFavorite: Bool
    /// Whether the pair appears in the tracked list.
    var isTracked: Bool
    /// User-controllable ordering within the tracked list.
    var sortOrder: Int
}

/// A currency's value expressed in USD plus its 24h change.
struct NormalizedRate: Codable, Hashable, Sendable {
    /// How many USD one unit of this currency is worth.
    var usdPerUnit: Double
    /// 24-hour change as a percentage (e.g. `2.14` for +2.14%).
    var change24h: Double
}

/// A point-in-time snapshot of all known rates.
struct RatesSnapshot: Codable, Hashable, Sendable {
    /// Map of uppercase currency code → normalized rate.
    var rates: [String: NormalizedRate]
    /// When this snapshot was produced.
    var updatedAt: Date
    /// The fiat-provider's reported date string (e.g. `"2025-06-01"`), if known.
    var fiatDate: String?
}

// MARK: - Catalog

extension Currency {
    /// The static set of supported currencies. Codes are UPPERCASE.
    ///
    /// `badgeHex` is set only for crypto (BTC `#f7931a`, ETH `#627eea`); fiat
    /// currencies leave it `nil`.
    static let supported: [Currency] = [
        Currency(code: "USD", symbol: "$", name: "US Dollar", kind: .fiat, badgeHex: nil),
        Currency(code: "BRL", symbol: "R$", name: "Brazilian Real", kind: .fiat, badgeHex: nil),
        Currency(code: "EUR", symbol: "€", name: "Euro", kind: .fiat, badgeHex: nil),
        Currency(code: "GBP", symbol: "£", name: "British Pound", kind: .fiat, badgeHex: nil),
        Currency(code: "JPY", symbol: "¥", name: "Japanese Yen", kind: .fiat, badgeHex: nil),
        Currency(code: "BTC", symbol: "₿", name: "Bitcoin", kind: .crypto, badgeHex: "#f7931a"),
        Currency(code: "ETH", symbol: "Ξ", name: "Ethereum", kind: .crypto, badgeHex: "#627eea"),
    ]

    /// Fast lookup of a currency by its uppercase code.
    static let byCode: [String: Currency] = Dictionary(
        uniqueKeysWithValues: supported.map { ($0.code, $0) }
    )
}

// MARK: - Seed pairs

extension CurrencyPair {
    /// The seven pairs seeded on first launch. `sortOrder == id`.
    static let defaultPairs: [CurrencyPair] = [
        CurrencyPair(id: 1, base: "USD", quote: "BRL", isFavorite: true, isTracked: true, sortOrder: 1),
        CurrencyPair(id: 2, base: "BTC", quote: "USD", isFavorite: true, isTracked: true, sortOrder: 2),
        CurrencyPair(id: 3, base: "EUR", quote: "BRL", isFavorite: false, isTracked: true, sortOrder: 3),
        CurrencyPair(id: 4, base: "ETH", quote: "USD", isFavorite: false, isTracked: true, sortOrder: 4),
        CurrencyPair(id: 5, base: "USD", quote: "JPY", isFavorite: false, isTracked: true, sortOrder: 5),
        CurrencyPair(id: 6, base: "GBP", quote: "USD", isFavorite: false, isTracked: false, sortOrder: 6),
        CurrencyPair(id: 7, base: "BTC", quote: "BRL", isFavorite: false, isTracked: false, sortOrder: 7),
    ]
}
