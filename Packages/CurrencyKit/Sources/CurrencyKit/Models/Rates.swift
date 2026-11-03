import Foundation

/// Where a rate came from.
public enum RateSource: String, Codable, Hashable, Sendable, CaseIterable {
    /// The daily currency API (fawazahmed0 currency-api). Fiat and long-tail crypto.
    case currencyAPI
    /// Coinbase market data (live crypto prices).
    case coinbase

    /// Human-readable attribution.
    public var displayName: String {
        switch self {
        case .currencyAPI: "currency-api"
        case .coinbase: "Coinbase"
        }
    }
}

/// The upstream sources the refresh engine talks to.
public enum RateSourceKind: String, Codable, Hashable, Sendable, CaseIterable {
    case fiat
    case crypto
}

/// One currency's value in USD and its 24h change.
public struct AssetRate: Codable, Hashable, Sendable {
    /// How many USD one unit is worth.
    public var usdPerUnit: Double
    /// Change of ``usdPerUnit`` over 24h as a fraction (`0.0214` = +2.14%).
    /// For daily fiat data this is the day-over-day change. `nil` when unknown.
    public var change24h: Double?
    /// When the value was observed (for daily data: midnight UTC of the data day).
    public var asOf: Date
    public var source: RateSource

    public init(usdPerUnit: Double, change24h: Double?, asOf: Date, source: RateSource) {
        self.usdPerUnit = usdPerUnit
        self.change24h = change24h
        self.asOf = asOf
        self.source = source
    }
}

/// All known rates at a point in time, normalized to USD per unit.
public struct RatesSnapshot: Codable, Hashable, Sendable {
    /// Rates keyed by uppercase code. `USD` is always present with `usdPerUnit == 1`.
    public var rates: [String: AssetRate]
    /// When data last arrived from any source (unchanged by refreshes that only failed).
    public var fetchedAt: Date
    /// The currency API's data day, if fiat data is present.
    public var fiatDay: CalendarDay?
    /// Sources that failed on the refresh that produced this snapshot (their
    /// previous values were kept). Empty when everything succeeded. Not persisted.
    public var issues: [RateSourceKind: CurrencyKitError]

    public init(
        rates: [String: AssetRate],
        fetchedAt: Date,
        fiatDay: CalendarDay? = nil,
        issues: [RateSourceKind: CurrencyKitError] = [:]
    ) {
        self.rates = rates
        self.fetchedAt = fetchedAt
        self.fiatDay = fiatDay
        self.issues = issues
    }

    /// Whether every source succeeded.
    public var isComplete: Bool { issues.isEmpty }

    /// USD per unit for `code`, or `nil` when unknown.
    public func usdPerUnit(_ code: String) -> Double? {
        rates[code.uppercased()]?.usdPerUnit
    }

    /// The live quote for `pair`, or `nil` when either side is unknown.
    public func quote(for pair: CurrencyPair) -> PairQuote? {
        guard let base = rates[pair.base], let quote = rates[pair.quote],
              let price = RateMath.crossRate(baseUSDPerUnit: base.usdPerUnit, quoteUSDPerUnit: quote.usdPerUnit) else {
            return nil
        }
        // USD is the anchor; it carries no information of its own about freshness.
        let legs = [(pair.base, base), (pair.quote, quote)].filter { $0.0 != "USD" }.map(\.1)
        let effective = legs.isEmpty ? [base] : legs
        return PairQuote(
            pair: pair,
            price: price,
            change24h: RateMath.pairChange(base: base.change24h, quote: quote.change24h),
            asOf: effective.map(\.asOf).min() ?? fetchedAt,
            sources: Array(Set(effective.map(\.source))).sorted { $0.rawValue < $1.rawValue }
        )
    }

    /// Converts `amount` of `from` into `to`; `nil` when a rate is missing.
    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let fromRate = usdPerUnit(from), let toRate = usdPerUnit(to) else { return nil }
        return RateMath.convert(amount, fromUSDPerUnit: fromRate, toUSDPerUnit: toRate)
    }

    private enum CodingKeys: String, CodingKey {
        case rates
        case fetchedAt
        case fiatDay
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rates = try container.decode([String: AssetRate].self, forKey: .rates)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        fiatDay = try container.decodeIfPresent(CalendarDay.self, forKey: .fiatDay)
        issues = [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rates, forKey: .rates)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encodeIfPresent(fiatDay, forKey: .fiatDay)
    }
}

/// The price of a pair, ready for display.
public struct PairQuote: Hashable, Sendable {
    public let pair: CurrencyPair
    /// Units of quote per one unit of base.
    public let price: Double
    /// 24h change of ``price`` as a fraction, or `nil` when unknown.
    public let change24h: Double?
    /// Freshness of the oldest leg (USD excluded).
    public let asOf: Date
    /// Sources that contributed (USD excluded), sorted.
    public let sources: [RateSource]

    public init(pair: CurrencyPair, price: Double, change24h: Double?, asOf: Date, sources: [RateSource]) {
        self.pair = pair
        self.price = price
        self.change24h = change24h
        self.asOf = asOf
        self.sources = sources
    }

    /// Up / down / flat, for arrows and colors.
    public var trend: Trend { Trend(change: change24h) }
}

/// Direction of a change, used for arrows and colors.
public enum Trend: String, Sendable, Hashable {
    case up
    case down
    case flat

    /// Flat for `nil`, non-finite, or changes that round to 0.00%.
    public init(change: Double?) {
        guard let change, change.isFinite, abs(change) >= 0.000_05 else {
            self = .flat
            return
        }
        self = change > 0 ? .up : .down
    }

    /// `▲` / `▼`, or `nil` when flat.
    public var arrow: String? {
        switch self {
        case .up: "▲"
        case .down: "▼"
        case .flat: nil
        }
    }

    /// SF Symbol name for the trend.
    public var systemImage: String {
        switch self {
        case .up: "arrowtriangle.up.fill"
        case .down: "arrowtriangle.down.fill"
        case .flat: "minus"
        }
    }
}

/// Pure exchange-rate math. All rates are USD per unit.
public enum RateMath {
    /// Units of quote per one base: `base / quote`. `nil` for missing, zero or non-finite inputs.
    public static func crossRate(baseUSDPerUnit: Double, quoteUSDPerUnit: Double) -> Double? {
        guard quoteUSDPerUnit > 0, baseUSDPerUnit > 0 else { return nil }
        let value = baseUSDPerUnit / quoteUSDPerUnit
        return value.isFinite ? value : nil
    }

    /// Converts `amount` between two currencies given their USD-per-unit rates.
    public static func convert(_ amount: Double, fromUSDPerUnit: Double, toUSDPerUnit: Double) -> Double? {
        guard let rate = crossRate(baseUSDPerUnit: fromUSDPerUnit, quoteUSDPerUnit: toUSDPerUnit) else { return nil }
        let value = amount * rate
        return value.isFinite ? value : nil
    }

    /// Change of a cross rate given each leg's change (fractions): `(1 + b) / (1 + q) - 1`.
    ///
    /// Subtracting the legs (`b - q`) is only a first-order approximation and drifts
    /// badly for volatile assets. Returns `nil` when either leg is unknown.
    public static func pairChange(base: Double?, quote: Double?) -> Double? {
        guard let base, let quote, 1 + quote != 0 else { return nil }
        let value = (1 + base) / (1 + quote) - 1
        return value.isFinite ? value : nil
    }

    /// Relative change from `old` to `new` as a fraction; `nil` when `old` is not positive.
    public static func change(from old: Double, to new: Double) -> Double? {
        guard old > 0, new.isFinite else { return nil }
        return new / old - 1
    }
}
