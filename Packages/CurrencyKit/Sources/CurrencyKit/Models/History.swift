import Foundation

/// Chart ranges.
public enum HistoryRange: String, Codable, CaseIterable, Sendable, Identifiable {
    case day = "24H"
    case week = "7D"
    case month = "30D"
    case quarter = "90D"

    public var id: String { rawValue }

    /// Label for segmented controls.
    public var displayName: String { rawValue }

    /// Length of the range.
    public var duration: TimeInterval { TimeInterval(days) * 86_400 }

    /// Length in days.
    public var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    /// Coinbase candle granularity (seconds). Every value keeps the request under 300 rows.
    var candleGranularity: Int {
        switch self {
        case .day: 900
        case .week: 3_600
        case .month: 21_600
        case .quarter: 86_400
        }
    }

    /// Spacing (in days) between daily fiat samples.
    var dailySampleStep: Int {
        self == .quarter ? 3 : 1
    }
}

/// One chart sample.
public struct HistoryPoint: Hashable, Sendable, Identifiable {
    public let date: Date
    /// Pair price (units of quote per base) at ``date``.
    public let value: Double

    public var id: Date { date }

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// A price series for a pair over a range, oldest first.
public struct PairHistory: Hashable, Sendable {
    public let pair: CurrencyPair
    public let range: HistoryRange
    public let points: [HistoryPoint]
    /// Sources that contributed.
    public let sources: [RateSource]

    public init(pair: CurrencyPair, range: HistoryRange, points: [HistoryPoint], sources: [RateSource]) {
        self.pair = pair
        self.range = range
        self.points = points
        self.sources = sources
    }

    /// Change from the first to the last point, as a fraction.
    public var change: Double? {
        guard let first = points.first?.value, let last = points.last?.value else { return nil }
        return RateMath.change(from: first, to: last)
    }

    public var low: Double? { points.map(\.value).min() }
    public var high: Double? { points.map(\.value).max() }
}
