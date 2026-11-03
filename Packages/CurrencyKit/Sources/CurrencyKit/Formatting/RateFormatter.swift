import Foundation

/// Locale-aware formatting for rates, amounts and percentage changes.
///
/// Styles are built once per formatter; keep one instance around (``CurrencyStore``
/// exposes ``CurrencyStore/formatter``) rather than creating one per cell.
public struct RateFormatter: Sendable {
    /// Shown for missing or non-finite values.
    public static let placeholder = "—"

    public let locale: Locale
    public let decimals: DecimalsPreference

    private let wholeStyle: FloatingPointFormatStyle<Double>
    private let fractionalStyle: FloatingPointFormatStyle<Double>
    private let tinyStyle: FloatingPointFormatStyle<Double>
    private let percentStyle: FloatingPointFormatStyle<Double>.Percent

    public init(locale: Locale = .autoupdatingCurrent, decimals: DecimalsPreference = .automatic) {
        self.locale = locale
        self.decimals = decimals
        let base = FloatingPointFormatStyle<Double>(locale: locale).grouping(.automatic)
        let extra = decimals == .precise ? 2 : 0
        wholeStyle = base.precision(.fractionLength(2 + extra))
        fractionalStyle = base.precision(.fractionLength(4 + extra))
        tinyStyle = base.precision(.significantDigits(2...(4 + extra)))
        percentStyle = FloatingPointFormatStyle<Double>.Percent(locale: locale)
            .precision(.fractionLength(2))
            .sign(strategy: .always(includingZero: false))
    }

    /// Formats a rate or amount with digits suited to its magnitude:
    /// `67,842.00`, `5.44`, `0.1838`, `0.0000131`.
    public func string(from value: Double?) -> String {
        guard let value, value.isFinite else { return Self.placeholder }
        let magnitude = abs(value)
        if magnitude == 0 || magnitude >= 1 { return value.formatted(wholeStyle) }
        if magnitude >= 0.01 { return value.formatted(fractionalStyle) }
        return value.formatted(tinyStyle)
    }

    /// Formats a fractional change as a signed percentage: `+2.14%`, `-0.31%`, `0.00%`.
    public func percent(_ change: Double?) -> String {
        guard let change, change.isFinite else { return Self.placeholder }
        return change.formatted(percentStyle)
    }

    /// `R$ 5.44`-style text: the currency symbol (or code) followed by the value.
    public func string(from value: Double?, symbol: String) -> String {
        "\(symbol) \(string(from: value))"
    }

    /// Plain text for the clipboard: Latin digits, the locale's decimal separator, no
    /// grouping and full precision with trailing zeros trimmed (`67842`, `5.4387`,
    /// `0.0000000829`). `nil` for missing or non-finite values.
    public func plainString(from value: Double?) -> String? {
        Self.plainString(from: value, locale: locale)
    }

    /// See ``plainString(from:)``. Also what ``AmountParser`` round-trips as editable text.
    public static func plainString(from value: Double?, locale: Locale) -> String? {
        guard let value, value.isFinite else { return nil }
        let number = value == 0 ? 0 : value // no "-0"
        let style = FloatingPointFormatStyle<Double>(locale: locale.withLatinDigits).grouping(.never)
        // Up to 8 decimals for values ≥ 1, up to 8 significant digits below 1 (tiny rates).
        let text = abs(number) >= 1
            ? number.formatted(style.precision(.fractionLength(0...8)))
            : number.formatted(style.precision(.significantDigits(1...8)))
        // Drop invisible bidi marks (Arabic and Persian put one before the minus sign).
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.properties.generalCategory != .format }))
    }
}

extension Locale {
    /// The same locale with Western (Latin) digits, e.g. `ar_EG` → `12.5` instead of `١٢٫٥`.
    var withLatinDigits: Locale {
        guard numberingSystem.identifier != "latn" else { return self }
        var components = Locale.Components(locale: self)
        components.numberingSystem = "latn"
        return Locale(components: components)
    }
}
