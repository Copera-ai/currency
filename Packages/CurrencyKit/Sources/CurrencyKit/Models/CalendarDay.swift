import Foundation

/// A calendar day in UTC, formatted as `YYYY-MM-DD` (the currency API's date format).
public struct CalendarDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Gregorian calendar pinned to UTC; the currency API publishes per UTC day.
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The UTC day containing `date`.
    public init(_ date: Date) {
        let parts = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses `YYYY-MM-DD`; returns `nil` for anything else.
    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// Midnight UTC at the start of this day.
    public var date: Date {
        Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    /// The day `count` days later (negative for earlier).
    public func adding(days count: Int) -> CalendarDay {
        CalendarDay(Self.utcCalendar.date(byAdding: .day, value: count, to: date) ?? date)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = CalendarDay(string: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid day \(raw)"))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
