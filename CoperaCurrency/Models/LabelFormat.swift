import Foundation

/// How a tracked pair is rendered as text in the menu bar.
///
/// - `pair`:   `"USD/BRL 5.42"` — the full pair code prefix.
/// - `symbol`: `"R$ 5.42"`      — the quote currency's display symbol prefix.
/// - `plain`:  `"5.42"`         — the bare formatted rate.
enum LabelFormat: String, CaseIterable, Sendable {
    case pair
    case symbol
    case plain

    /// Human-readable name for settings UI.
    var displayName: String {
        switch self {
        case .pair: return "Pair"
        case .symbol: return "Symbol"
        case .plain: return "Value"
        }
    }
}

/// The directional trend of a pair's 24h change, used to pick the menu-bar arrow.
enum Trend: Sendable, Equatable {
    case up
    case down
    case flat

    /// Build a trend from a change percentage. Treats `0` (and non-finite) as flat.
    init(change: Double) {
        if !change.isFinite || change == 0 {
            self = .flat
        } else {
            self = change > 0 ? .up : .down
        }
    }

    /// The arrow glyph, or `nil` when flat (no arrow shown).
    var arrow: String? {
        switch self {
        case .up: return "▲"
        case .down: return "▼"
        case .flat: return nil
        }
    }
}

extension LabelFormat {
    /// Compute the leading text prefix (everything before the formatted rate)
    /// for a pair under this format. Returns an empty string for `.plain`.
    func prefix(for pair: CurrencyPair) -> String {
        switch self {
        case .pair:
            return "\(pair.base)/\(pair.quote)"
        case .symbol:
            // Quote-currency symbol (the unit the rate is expressed in).
            return Currency.byCode[pair.quote]?.symbol ?? pair.quote
        case .plain:
            return ""
        }
    }
}
