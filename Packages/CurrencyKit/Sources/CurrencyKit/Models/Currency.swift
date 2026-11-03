import Foundation

/// Whether a currency is a government-issued fiat currency or a cryptocurrency.
public enum CurrencyKind: String, Codable, Hashable, Sendable {
    case fiat
    case crypto
}

/// A currency in the ``CurrencyCatalog``.
public struct Currency: Hashable, Sendable, Identifiable {
    /// Uppercase code, e.g. `"USD"`, `"BTC"`.
    public let code: String
    /// English display name, e.g. `"US Dollar"`.
    public let name: String
    /// Short display symbol, e.g. `"$"`, `"R$"`, `"₿"`. Falls back to the code.
    public let symbol: String
    /// Fiat vs. crypto.
    public let kind: CurrencyKind
    /// Flag emoji for fiat currencies whose issuing region is known (`nil` for crypto).
    public let flag: String?
    /// Brand color as `#RRGGBB` for crypto assets (`nil` for fiat).
    public let brandColorHex: String?
    /// Coinbase product used for live price and 24h change (e.g. `"BTC-USD"`), when listed.
    public let coinbaseProductID: String?

    public var id: String { code }

    /// The flag for fiat, otherwise the symbol. Handy as a compact visual prefix.
    public var badge: String { flag ?? symbol }

    public init(
        code: String,
        name: String,
        symbol: String,
        kind: CurrencyKind,
        flag: String? = nil,
        brandColorHex: String? = nil,
        coinbaseProductID: String? = nil
    ) {
        self.code = code.uppercased()
        self.name = name
        self.symbol = symbol
        self.kind = kind
        self.flag = flag
        self.brandColorHex = brandColorHex
        self.coinbaseProductID = coinbaseProductID
    }
}
