@testable import CurrencyKit
import Foundation
import Testing

@Suite("Formatting and parsing")
struct FormattingTests {
    private static let enUS = Locale(identifier: "en_US")
    private static let ptBR = Locale(identifier: "pt_BR")
    private static let deDE = Locale(identifier: "de_DE")
    private static let jaJP = Locale(identifier: "ja_JP")
    private static let arEG = Locale(identifier: "ar_EG")
    private static let arSA = Locale(identifier: "ar_SA")
    private static let faIR = Locale(identifier: "fa_IR")
    private static let enIN = Locale(identifier: "en_IN")

    /// Normalizes the no-break spaces some locales use before `%`.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test(arguments: [
        (enUS, ["67,842.00", "5.42", "0.1845", "0.006357", "0.0000000829", "-5.42", "1,234.50", "0.00"]),
        (ptBR, ["67.842,00", "5,42", "0,1845", "0,006357", "0,0000000829", "-5,42", "1.234,50", "0,00"]),
        (deDE, ["67.842,00", "5,42", "0,1845", "0,006357", "0,0000000829", "-5,42", "1.234,50", "0,00"]),
        (jaJP, ["67,842.00", "5.42", "0.1845", "0.006357", "0.0000000829", "-5.42", "1,234.50", "0.00"]),
    ])
    func ratesByMagnitude(locale: Locale, expected: [String]) {
        let formatter = RateFormatter(locale: locale)
        let values: [Double] = [67842, 5.42, 0.1845, 0.006357, 0.0000000829, -5.42, 1234.5, 0]
        #expect(values.map { formatter.string(from: $0) } == expected)
    }

    @Test func tinyValuesKeepSignificantDigits() {
        let formatter = RateFormatter(locale: Self.enUS)
        // BTC per JPY ≈ 8.29e-8; SHIB ≈ 4.53e-6 USD.
        #expect(formatter.string(from: 1 / 157.84 / 76_372.94) == "0.00000008296")
        #expect(formatter.string(from: 0.00000453) == "0.00000453")
        #expect(formatter.string(from: 0.000005) == "0.0000050")
        #expect(formatter.string(from: 0.00000456789) == "0.000004568")
    }

    @Test func preciseDecimals() {
        let formatter = RateFormatter(locale: Self.enUS, decimals: .precise)
        #expect(formatter.string(from: 5.44059239) == "5.4406")
        #expect(formatter.string(from: 0.18380) == "0.183800")
        #expect(formatter.string(from: 0.00000456789) == "0.00000456789")
    }

    @Test func nonFiniteAndMissing() {
        let formatter = RateFormatter(locale: Self.enUS)
        #expect(formatter.string(from: .nan) == "—")
        #expect(formatter.string(from: .infinity) == "—")
        #expect(formatter.string(from: nil) == "—")
        #expect(formatter.percent(nil) == "—")
        #expect(formatter.string(from: 5.4, symbol: "R$") == "R$ 5.40")
    }

    @Test(arguments: [
        (enUS, ["+2.14%", "-0.31%", "0.00%"]),
        (ptBR, ["+2,14%", "-0,31%", "0,00%"]),
        (deDE, ["+2,14 %", "-0,31 %", "0,00 %"]),
        (jaJP, ["+2.14%", "-0.31%", "0.00%"]),
    ])
    func percentages(locale: Locale, expected: [String]) {
        let formatter = RateFormatter(locale: locale)
        #expect([0.0214, -0.0031, 0].map { plain(formatter.percent($0)) } == expected)
    }

    // MARK: - Parser

    @Test(arguments: [
        (enUS, "1,234.50", 1234.5), (enUS, "1234.5", 1234.5), (enUS, "1,500", 1500), (enUS, "1,5", 1.5), (enUS, "1,234,567.8", 1_234_567.8),
        (ptBR, "1.234,50", 1234.5), (ptBR, "1234,5", 1234.5), (ptBR, "1.500", 1500), (ptBR, "5.5", 5.5), (ptBR, "1,234.50", 1234.5),
        (deDE, "1.234,50", 1234.5), (deDE, "0,25", 0.25), (deDE, "1.000.000", 1_000_000),
        (jaJP, "1,234.5", 1234.5), (jaJP, "１００", 100),
        (enUS, ".5", 0.5), (enUS, "5.", 5), (enUS, "  42 ", 42),
        // Arabic-Indic / Persian digits with the Arabic decimal (٫) and thousands (٬) separators.
        (arEG, "١٢٫٥", 12.5), (arEG, "١٬٢٣٤٫٥", 1234.5), (arEG, "12.5", 12.5), (arEG, "12.500", 12.5), (arEG, "1234", 1234),
        (arSA, "١٢٫٥", 12.5), (arSA, "١٠٠", 100),
        (faIR, "۱۲٫۵", 12.5), (faIR, "۱٬۰۰۰", 1000), (faIR, "\u{200E}−۵", -5),
        // Indian grouping (lakh/crore).
        (enIN, "12,34,567.5", 1_234_567.5), (enIN, "1,00,000", 100_000), (enIN, "1,000", 1000), (enIN, "1,23,45,678", 12_345_678),
        (enUS, "١٢.٥", 12.5),
    ])
    func parsesLocaleNumbers(locale: Locale, text: String, expected: Double) {
        #expect(AmountParser(locale: locale).parse(text) == expected)
    }

    @Test(arguments: [
        ("100 + 20*2", 140.0), ("(1+2)*3", 9), ("-5 + 2", -3), ("10/4", 2.5), ("2 × 3 ÷ 4", 1.5),
        ("-(2+3)", -5), ("2*-3", -6), ("1,000 - 0.5", 999.5), ("((7))", 7), ("100 − 1", 99),
    ])
    func evaluatesExpressions(text: String, expected: Double) {
        #expect(AmountParser(locale: Self.enUS).parse(text) == expected)
    }

    @Test func evaluatesExpressionsInPortuguese() {
        let parser = AmountParser(locale: Self.ptBR)
        #expect(parser.parse("1.234,5 * 2") == 2469)
        #expect(parser.parse("10,5 + 0,5") == 11)
    }

    @Test(arguments: ["", "abc", "1.2.3", "100+", "(1+2", "1+2)", "10/0", "1,23,4", "$100", "1e5", "--", "()", "12,345,67", "1,23,456,789"])
    func rejectsInvalidInput(text: String) {
        #expect(AmountParser(locale: Self.enUS).parse(text) == nil)
        #expect(AmountParser(locale: Self.enIN).parse(text) == nil)
    }

    @Test(arguments: [enUS, ptBR, deDE, jaJP, arEG, arSA, faIR, enIN])
    func editableStringRoundTrips(locale: Locale) {
        let parser = AmountParser(locale: locale)
        for value in [12.5, 1_234_567.5, 100_000, 0.125, 1.5, 1500, 0.00012345, -42.75] {
            let text = parser.editableString(value)
            #expect(text.allSatisfy { !$0.isNumber || $0.isASCII }, "Latin digits: \(text)")
            #expect(!text.contains(where: { [",", "\u{066C}"].contains($0) }) || locale.decimalSeparator == ",", "no grouping: \(text)")
            #expect(parser.parse(text) == value, "\(locale.identifier): \(text)")
        }
        #expect(parser.editableString(0) == "")
    }

    @Test func editableStringUsesLocaleDecimalSeparator() {
        #expect(AmountParser(locale: Self.enUS).editableString(1234.5) == "1234.5")
        #expect(AmountParser(locale: Self.ptBR).editableString(1234.5) == "1234,5")
        #expect(AmountParser(locale: Self.arEG).editableString(1234.5) == "1234.5")
        #expect(AmountParser(locale: Self.enIN).editableString(1_234_567) == "1234567")
    }

    // MARK: - Plain (clipboard) strings

    @Test func plainStringKeepsPrecisionWithoutGrouping() {
        let formatter = RateFormatter(locale: Self.enUS)
        #expect(formatter.plainString(from: 5.4387) == "5.4387")
        #expect(formatter.plainString(from: 67842) == "67842")
        #expect(formatter.plainString(from: 1_234_567.123456789) == "1234567.12345679")
        #expect(formatter.plainString(from: 0.0000000829) == "0.0000000829")
        #expect(formatter.plainString(from: 0.18380123456) == "0.18380123")
        #expect(formatter.plainString(from: -5.4) == "-5.4")
        #expect(formatter.plainString(from: 0) == "0")
        #expect(formatter.plainString(from: -0.0) == "0")
        #expect(formatter.plainString(from: .nan) == nil)
        #expect(formatter.plainString(from: nil) == nil)
        #expect(RateFormatter(locale: Self.ptBR).plainString(from: 67842.5) == "67842,5")
        #expect(RateFormatter(locale: Self.arEG).plainString(from: 5.4387) == "5.4387")
        #expect(RateFormatter(locale: Self.faIR).plainString(from: -5.4387) == "−5.4387")
        #expect(RateFormatter(locale: Self.enIN).plainString(from: 1_234_567.5) == "1234567.5")
    }

    @Test func rejectsHugeInput() {
        #expect(AmountParser(locale: Self.enUS).parse(String(repeating: "1+", count: 200) + "1") == nil)
        #expect(AmountParser(locale: Self.enUS).parse(String(repeating: "(", count: 40) + "1" + String(repeating: ")", count: 40)) == nil)
    }

    // MARK: - Relative time

    @Test func updatedText() {
        let now = fixtureNow
        #expect(CurrencyStore.updatedText(lastUpdated: nil, now: now, locale: Self.enUS) == "Not updated yet")
        #expect(CurrencyStore.updatedText(lastUpdated: now.addingTimeInterval(-10), now: now, locale: Self.enUS) == "Updated just now")
        #expect(CurrencyStore.updatedText(lastUpdated: now.addingTimeInterval(-300), now: now, locale: Self.enUS) == "Updated 5 minutes ago")
        #expect(CurrencyStore.updatedText(lastUpdated: now.addingTimeInterval(-7_200), now: now, locale: Self.enUS) == "Updated 2 hours ago")
    }

    @Test func menuBarLabelText() {
        #expect(MenuBarLabel(prefix: "USD/BRL", value: "5.44", trend: .up, showsArrow: true).text == "USD/BRL 5.44 ▲")
        #expect(MenuBarLabel(prefix: "", value: "5.44", trend: .down, showsArrow: false).text == "5.44")
        #expect(MenuBarLabel(prefix: "R$", value: "5.44", trend: .flat, showsArrow: true).text == "R$ 5.44")
    }
}
