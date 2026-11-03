import Foundation

/// Parses amounts typed by the user, honoring the locale's separators, plus simple
/// arithmetic (`+ - * / × ÷`, parentheses, unary minus).
///
/// Separators are interpreted leniently: `1.234,50` (pt_BR), `1,234.50` (en_US),
/// `12,34,567.5` (en_IN), `١٬٢٣٤٫٥` (ar_EG) and an unambiguous foreign decimal like
/// `5.5` in pt_BR all parse. A lone grouping separator followed by exactly three digits
/// (`1,500` in en_US) is grouping. Any Unicode decimal digits (Arabic-Indic, Persian,
/// full-width, …) are accepted.
public struct AmountParser: Sendable {
    public let locale: Locale
    /// The locale's decimal separators, native and with Latin digits (they differ in
    /// Arabic: `٫` vs `.`), plus the Arabic decimal separator.
    private let decimalSeparators: Set<Character>
    private let separators: Set<Character>

    private static let maxLength = 256
    private static let maxDepth = 32

    public init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
        let latin = locale.withLatinDigits
        let decimals: [Character] = [locale.decimalSeparator, latin.decimalSeparator].compactMap { $0?.first } + ["\u{066B}"]
        let groupings: [Character] = [locale.groupingSeparator, latin.groupingSeparator].compactMap { $0?.first }
        // `'`/`’` (de_CH), no-break spaces (fr_FR), Arabic thousands separator `٬`.
        let common: [Character] = [".", ",", "'", "’", "\u{00A0}", "\u{202F}", "\u{066C}"]
        decimalSeparators = Set(decimals)
        separators = Set(decimals + groupings + common)
    }

    /// `value` as text the user can edit and this parser reads back exactly: Latin
    /// digits, the locale's decimal separator, no grouping, up to 8 decimals (`1234.5`,
    /// `1234,5`). Zero is empty, so the field shows its placeholder.
    public func editableString(_ value: Double) -> String {
        guard value != 0 else { return "" }
        return RateFormatter.plainString(from: value, locale: locale) ?? ""
    }

    /// The value of `text`, or `nil` when it is empty, malformed, or not finite
    /// (e.g. division by zero).
    public func parse(_ text: String) -> Double? {
        guard text.count <= Self.maxLength else { return nil }
        // Full-width operators (e.g. from a Japanese IME) → ASCII.
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        guard let tokens = tokenize(Self.normalizingDigits(halfWidth)), !tokens.isEmpty else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(depth: 0), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    // MARK: - Tokens

    enum Token: Equatable {
        case number(Double)
        case op(Character)
        case open
        case close
    }

    private func isSeparator(_ char: Character) -> Bool {
        separators.contains(char)
    }

    /// Maps every Unicode decimal digit (`١`, `۱`, `１`, …) to ASCII and drops invisible
    /// format characters such as the bidi marks Arabic and Persian put before a minus.
    static func normalizingDigits(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for char in text {
            guard char.unicodeScalars.count == 1, let scalar = char.unicodeScalars.first else {
                result.append(char)
                continue
            }
            switch scalar.properties.generalCategory {
            case .decimalNumber:
                if let digit = char.wholeNumberValue { result += String(digit) } else { result.append(char) }
            case .format:
                continue
            default:
                result.append(char)
            }
        }
        return result
    }

    func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char.isWhitespace && !isSeparator(char) {
                index = text.index(after: index)
                continue
            }
            if char.isASCIIDigit || isSeparator(char) {
                var end = index
                while end < text.endIndex, text[end].isASCIIDigit || isSeparator(text[end]) {
                    end = text.index(after: end)
                }
                guard let number = number(from: String(text[index..<end])) else { return nil }
                tokens.append(.number(number))
                index = end
                continue
            }
            switch char {
            case "+": tokens.append(.op("+"))
            case "-", "−", "–": tokens.append(.op("-"))
            case "*", "×", "x", "X": tokens.append(.op("*"))
            case "/", "÷": tokens.append(.op("/"))
            case "(": tokens.append(.open)
            case ")": tokens.append(.close)
            default: return nil
            }
            index = text.index(after: index)
        }
        return tokens
    }

    /// Interprets one run of digits and separators.
    func number(from raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\u{00A0}\u{202F}"))
        let separators = trimmed.filter { !$0.isASCIIDigit }
        guard trimmed.contains(where: \.isASCIIDigit) else { return nil }

        var decimalChar: Character?
        if let last = separators.last {
            let kinds = Set(separators)
            if kinds.count > 1 {
                // Mixed separators: the last one is the decimal point and must appear once.
                guard separators.filter({ $0 == last }).count == 1 else { return nil }
                decimalChar = last
            } else if separators.count == 1 {
                let digitsAfter = trimmed.split(separator: last, omittingEmptySubsequences: false).last?.count ?? 0
                let looksGrouped = digitsAfter == 3 && !decimalSeparators.contains(last) && trimmed.first != last
                decimalChar = looksGrouped ? nil : last
            }
        }

        let integerPart = decimalChar.flatMap { trimmed.split(separator: $0, omittingEmptySubsequences: false).first.map(String.init) } ?? trimmed
        let groups = integerPart.split(omittingEmptySubsequences: false, whereSeparator: isSeparator)
        guard groups.count == 1 || Self.isValidGrouping(groups) else { return nil }

        var normalized = ""
        for char in trimmed {
            if char.isASCIIDigit {
                normalized.append(char)
            } else if char == decimalChar {
                normalized.append(".")
            }
        }
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if normalized.hasSuffix(".") { normalized += "0" }
        return Double(normalized)
    }

    /// The last group has 3 digits and the ones between have 3 (`1,234,567`) or 2
    /// (Indian `12,34,567`) digits, so `1,23,4` stays invalid.
    private static func isValidGrouping(_ groups: [Substring]) -> Bool {
        guard let first = groups.first, !first.isEmpty, groups.last?.count == 3 else { return false }
        let inner = groups.dropFirst().dropLast()
        return inner.allSatisfy { $0.count == 3 } || inner.allSatisfy { $0.count == 2 }
    }

    // MARK: - Recursive descent

    private struct Parser {
        let tokens: [Token]
        var position = 0

        var isAtEnd: Bool { position == tokens.count }

        mutating func parseExpression(depth: Int) -> Double? {
            guard depth < AmountParser.maxDepth, var value = parseTerm(depth: depth) else { return nil }
            while position < tokens.count, case .op(let op) = tokens[position], op == "+" || op == "-" {
                position += 1
                guard let rhs = parseTerm(depth: depth) else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm(depth: Int) -> Double? {
            guard var value = parseFactor(depth: depth) else { return nil }
            while position < tokens.count, case .op(let op) = tokens[position], op == "*" || op == "/" {
                position += 1
                guard let rhs = parseFactor(depth: depth) else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        mutating func parseFactor(depth: Int) -> Double? {
            guard position < tokens.count else { return nil }
            let token = tokens[position]
            position += 1
            switch token {
            case .number(let value):
                return value
            case .op("-"):
                return parseFactor(depth: depth + 1).map { -$0 }
            case .op("+"):
                return parseFactor(depth: depth + 1)
            case .open:
                guard let value = parseExpression(depth: depth + 1),
                      position < tokens.count, tokens[position] == .close else { return nil }
                position += 1
                return value
            default:
                return nil
            }
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
