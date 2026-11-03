// Regenerates Sources/CurrencyKit/Resources/fiat-catalog.json.
//
// Usage (from Packages/CurrencyKit):
//   curl -s https://latest.currency-api.pages.dev/v1/currencies.min.json -o /tmp/names.json
//   curl -s https://latest.currency-api.pages.dev/v1/currencies/usd.min.json -o /tmp/usd.json
//   swift Scripts/generate-fiat-catalog.swift /tmp/names.json /tmp/usd.json > Sources/CurrencyKit/Resources/fiat-catalog.json
//
// Fiat = codes that are both in Foundation's common ISO 4217 list and quoted by the
// currency API. Names come from the API's currencies.json; symbols come from the
// en_US locale, falling back to the first native locale that has a real symbol.
import Foundation

struct Entry: Encodable {
    let code: String
    let name: String
    let symbol: String
}

let args = CommandLine.arguments
let names = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let usd = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as? [String: Any]
let quoted = Set(((usd?["usd"] as? [String: Any]) ?? [:]).keys).union(["usd"])
let common = Set(Locale.commonISOCurrencyCodes.map { $0.lowercased() })
// Precious metals, SDR, and currencies that were replaced or abolished.
let excluded: Set<String> = ["xag", "xau", "xpd", "xpt", "xdr", "hrk", "vef", "sll", "cuc"]
let nameOverrides = ["xcg": "Caribbean Guilder", "aed": "UAE Dirham", "bob": "Bolivian Boliviano"]

/// Drops bidi marks, zero-width spaces and other invisible format characters.
func clean(_ symbol: String?) -> String {
    let scalars = (symbol ?? "").unicodeScalars.filter { $0.properties.generalCategory != .format }
    return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
}

let formatter = NumberFormatter()
formatter.numberStyle = .currency
var nativeSymbols: [String: String] = [:]
for identifier in Locale.availableIdentifiers.sorted() {
    let locale = Locale(identifier: identifier)
    guard let code = locale.currency?.identifier, nativeSymbols[code] == nil else { continue }
    formatter.locale = locale
    formatter.currencyCode = code
    let symbol = clean(formatter.currencySymbol)
    if !symbol.isEmpty, symbol != code { nativeSymbols[code] = symbol }
}

formatter.locale = Locale(identifier: "en_US")
let entries: [Entry] = names.keys
    .filter { common.contains($0) && quoted.contains($0) && !excluded.contains($0) }
    .sorted()
    .compactMap { key in
        let code = key.uppercased()
        let name = nameOverrides[key] ?? names[key] ?? ""
        guard !name.isEmpty else { return nil }
        formatter.currencyCode = code
        var symbol = clean(formatter.currencySymbol)
        if symbol.isEmpty || symbol == code { symbol = nativeSymbols[code] ?? code }
        return Entry(code: code, name: name, symbol: symbol)
    }

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(entries))
FileHandle.standardOutput.write(Data("\n".utf8))
