import Foundation

/// One day of currency-API data: units of each currency per 1 USD.
struct FiatSnapshot: Hashable, Sendable {
    let day: CalendarDay
    /// Uppercase code → units per USD (always positive). Includes `USD = 1`.
    let unitsPerUSD: [String: Double]

    /// USD per unit for `code`.
    func usdPerUnit(_ code: String) -> Double? {
        guard let units = unitsPerUSD[code.uppercased()], units > 0 else { return nil }
        return 1 / units
    }

    /// Decodes `{"date":"YYYY-MM-DD","usd":{"brl":5.44,…}}`. Entries that are not
    /// positive numbers are skipped instead of failing the whole payload.
    static func decode(_ data: Data) throws -> FiatSnapshot {
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard let day = CalendarDay(string: payload.date) else {
                throw CurrencyKitError.decoding("Invalid date \(payload.date)")
            }
            var rates: [String: Double] = ["USD": 1]
            for (code, value) in payload.usd {
                if let value, value > 0, value.isFinite { rates[code.uppercased()] = value }
            }
            guard rates.count > 1 else { throw CurrencyKitError.decoding("Empty rates map") }
            return FiatSnapshot(day: day, unitsPerUSD: rates)
        } catch let error as CurrencyKitError {
            throw error
        } catch {
            throw CurrencyKitError.decoding("Fiat snapshot: \(error)")
        }
    }

    private struct Payload: Decodable {
        let date: String
        let usd: [String: Double?]

        private enum CodingKeys: String, CodingKey {
            case date
            case usd
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(String.self, forKey: .date)
            let nested = try container.nestedContainer(keyedBy: AnyKey.self, forKey: .usd)
            var values: [String: Double?] = [:]
            for key in nested.allKeys {
                values[key.stringValue] = try? nested.decode(Double.self, forKey: key)
            }
            usd = values
        }
    }
}

/// Live price and 24h change for one Coinbase product.
struct CoinbaseTicker: Hashable, Sendable {
    /// e.g. `"BTC-USD"`.
    let productID: String
    /// USD per unit.
    let price: Double
    /// 24h change as a fraction, when Coinbase reports one.
    let change24h: Double?

    /// Base asset code, e.g. `"BTC"`.
    var baseCode: String { String(productID.split(separator: "-").first ?? "") }

    /// Decodes the `market/products` response. Malformed products are dropped
    /// individually so one bad entry never hides the others.
    static func decodeList(_ data: Data) throws -> [CoinbaseTicker] {
        do {
            let payload = try JSONDecoder().decode(ProductsPayload.self, from: data)
            return payload.products.compactMap(\.value).compactMap(\.ticker)
        } catch {
            throw CurrencyKitError.decoding("Coinbase products: \(error)")
        }
    }

    private struct ProductsPayload: Decodable {
        let products: [Lossy<Product>]
    }

    private struct Product: Decodable {
        let product_id: String
        let price: String
        let price_percentage_change_24h: String?

        var ticker: CoinbaseTicker? {
            guard let price = Double(price), price > 0, price.isFinite else { return nil }
            let percent = price_percentage_change_24h.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
            return CoinbaseTicker(productID: product_id, price: price, change24h: percent.map { $0 / 100 })
        }
    }
}

/// One OHLC candle from the Coinbase Exchange API.
struct Candle: Hashable, Sendable {
    let time: Date
    let low: Double
    let high: Double
    let open: Double
    let close: Double

    /// Decodes `[[time, low, high, open, close, volume], …]` and returns candles oldest first.
    static func decodeList(_ data: Data) throws -> [Candle] {
        let rows: [[Double]]
        do {
            rows = try JSONDecoder().decode([[Double]].self, from: data)
        } catch {
            throw CurrencyKitError.decoding("Coinbase candles: \(error)")
        }
        return rows
            .compactMap { row -> Candle? in
                guard row.count >= 5, row[4] > 0 else { return nil }
                return Candle(time: Date(timeIntervalSince1970: row[0]), low: row[1], high: row[2], open: row[3], close: row[4])
            }
            .sorted { $0.time < $1.time }
    }
}

/// Decodes a value or yields `nil` without failing the enclosing container.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// A coding key for maps with arbitrary keys.
struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
