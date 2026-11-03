import Foundation

/// A base → quote pair, e.g. USD/BRL ("how many BRL is one USD").
///
/// Codes are normalized to uppercase. The identity is the pair itself, so a list
/// of pairs can never contain duplicates.
public struct CurrencyPair: Codable, Hashable, Sendable, Identifiable, CustomStringConvertible {
    /// Base ("from") currency code.
    public let base: String
    /// Quote ("to") currency code.
    public let quote: String

    public init(base: String, quote: String) {
        self.base = base.uppercased()
        self.quote = quote.uppercased()
    }

    /// Stable identifier, e.g. `"USD/BRL"`.
    public var id: String { "\(base)/\(quote)" }

    public var description: String { id }

    /// The same pair with base and quote swapped.
    public var inverted: CurrencyPair { CurrencyPair(base: quote, quote: base) }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            base: try container.decode(String.self, forKey: .base),
            quote: try container.decode(String.self, forKey: .quote)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case base
        case quote
    }
}

/// A pair the user tracks, plus its per-pair preferences.
public struct TrackedPair: Codable, Hashable, Sendable, Identifiable {
    public var pair: CurrencyPair
    /// Starred by the user.
    public var isFavorite: Bool
    /// Shown as its own item in the menu bar.
    public var showInMenuBar: Bool

    public var id: CurrencyPair.ID { pair.id }

    public init(_ pair: CurrencyPair, isFavorite: Bool = false, showInMenuBar: Bool = false) {
        self.pair = pair
        self.isFavorite = isFavorite
        self.showInMenuBar = showInMenuBar
    }

    /// Pairs seeded on first launch (no saved state and nothing to migrate).
    public static let defaults: [TrackedPair] = [
        TrackedPair(CurrencyPair(base: "USD", quote: "BRL"), isFavorite: true, showInMenuBar: true),
        TrackedPair(CurrencyPair(base: "EUR", quote: "BRL")),
        TrackedPair(CurrencyPair(base: "BTC", quote: "USD"), isFavorite: true, showInMenuBar: true),
        TrackedPair(CurrencyPair(base: "ETH", quote: "USD")),
        TrackedPair(CurrencyPair(base: "USD", quote: "JPY")),
        TrackedPair(CurrencyPair(base: "GBP", quote: "USD")),
    ]
}
