import Foundation

/// Supplies USD-per-unit exchange rates for a set of currency codes.
///
/// Implementations are responsible for normalizing their backend's convention
/// into the canonical "how many USD one unit is worth" form. The result map is
/// keyed by UPPERCASE currency code.
protocol RatesProvider: Sendable {
    /// Fetch USD-per-unit rates for the given uppercase codes.
    ///
    /// Implementations may return a superset or subset of `codes` depending on
    /// what the backend provides; callers should only rely on requested codes.
    func fetchUSDPerUnit(for codes: Set<String>) async throws -> [String: Double]

    /// The backend's reported "as-of" date for the given codes, if it exposes
    /// one (e.g. Fawaz's daily `date` field). Used by the store to roll the 24h
    /// baseline when the source's day changes.
    ///
    /// Defaults to `nil` (date unknown); only date-bearing providers override it.
    /// Errors are swallowed to `nil` so this can never break a refresh.
    func fetchAsOfDate(for codes: Set<String>) async -> String?
}

extension RatesProvider {
    /// Default: the provider has no notion of an "as-of" date.
    func fetchAsOfDate(for codes: Set<String>) async -> String? { nil }
}

/// Errors surfaced by the built-in providers.
enum RatesProviderError: Error, Sendable {
    /// The HTTP response was missing or had a non-2xx status code.
    case badResponse
    /// All configured endpoints failed.
    case allEndpointsFailed
    /// The payload could not be decoded into the expected shape.
    case malformedPayload
}

// MARK: - Shared URLSession

extension URLSession {
    /// A short-timeout, non-connectivity-waiting session for rate fetches.
    static func ratesSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }
}

// MARK: - Dynamic coding key

/// A `CodingKey` that accepts any string key, used to read maps with unknown
/// keys (e.g. the base-keyed currency map from the Fawaz API).
struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Fawaz fiat provider

/// Fetches fiat rates from the free `@fawazahmed0/currency-api`.
///
/// The API reports rates as "units of currency per 1 USD" (e.g. `brl: 5.15`),
/// so this provider INVERTS each value to produce USD-per-unit. `USD` is forced
/// to `1`.
struct FawazFiatProvider: RatesProvider {
    /// Primary jsDelivr-hosted endpoint.
    static let primaryURL = URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json")!
    /// Cloudflare Pages fallback endpoint.
    static let fallbackURL = URL(string: "https://latest.currency-api.pages.dev/v1/currencies/usd.json")!

    let session: URLSession

    init(session: URLSession = .ratesSession()) {
        self.session = session
    }

    /// The decodable shape of the Fawaz `usd.json` payload.
    ///
    /// Shape: `{"date":"2025-06-01","usd":{"brl":5.15,...}}` with lowercase
    /// codes. `rates` preserves the lowercase keys as-is.
    struct Payload: Decodable, Sendable {
        let date: String
        let rates: [String: Double]

        private enum TopKeys: String, CodingKey {
            case date
            case usd
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: TopKeys.self)
            self.date = try container.decode(String.self, forKey: .date)

            // The base-keyed map ("usd") has arbitrary lowercase currency keys.
            let nested = try container.nestedContainer(keyedBy: DynamicKey.self, forKey: .usd)
            var parsed: [String: Double] = [:]
            for key in nested.allKeys {
                parsed[key.stringValue] = try nested.decode(Double.self, forKey: key)
            }
            self.rates = parsed
        }
    }

    /// Pure decode + normalization: parse raw `Data` into USD-per-unit form.
    ///
    /// Every present key is uppercased and inverted (`1 / value`); `USD` is
    /// forced to `1`. Exposed for testing without network access.
    static func decode(_ data: Data) throws -> (date: String, usdPerUnit: [String: Double]) {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        var usdPerUnit: [String: Double] = [:]
        for (code, value) in payload.rates where value != 0 {
            usdPerUnit[code.uppercased()] = 1 / value
        }
        usdPerUnit["USD"] = 1
        return (payload.date, usdPerUnit)
    }

    func fetchUSDPerUnit(for codes: Set<String>) async throws -> [String: Double] {
        let data = try await fetchData()
        let result = try Self.decode(data)
        return result.usdPerUnit
    }

    /// Fetch the date string and full USD-per-unit map (date is needed by the
    /// store for daily-baseline rolling).
    func fetchDatedRates() async throws -> (date: String, usdPerUnit: [String: Double]) {
        let data = try await fetchData()
        return try Self.decode(data)
    }

    /// Surface Fawaz's daily `date` so the store can roll the 24h baseline when
    /// the source's day changes. Failures are swallowed to `nil`.
    func fetchAsOfDate(for codes: Set<String>) async -> String? {
        (try? await fetchDatedRates())?.date
    }

    private func fetchData() async throws -> Data {
        for url in [Self.primaryURL, Self.fallbackURL] {
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    continue
                }
                return data
            } catch {
                continue
            }
        }
        throw RatesProviderError.allEndpointsFailed
    }
}

// MARK: - Coinbase crypto provider

/// Fetches crypto rates (BTC, ETH) from Coinbase's public exchange-rates API.
///
/// The endpoint `exchange-rates?currency=BTC` reports `rates.USD` as the USD
/// value of 1 BTC directly, so this provider does NOT invert (the opposite
/// convention to ``FawazFiatProvider``).
struct CoinbaseCryptoProvider: RatesProvider {
    /// Crypto codes this provider fetches by default.
    static let defaultCryptoCodes: [String] = ["BTC", "ETH"]

    let session: URLSession
    /// Crypto codes to query when `fetchUSDPerUnit` is asked for a broad set.
    let cryptoCodes: [String]

    init(session: URLSession = .ratesSession(), cryptoCodes: [String] = CoinbaseCryptoProvider.defaultCryptoCodes) {
        self.session = session
        self.cryptoCodes = cryptoCodes
    }

    private static func url(for currency: String) -> URL {
        URL(string: "https://api.coinbase.com/v2/exchange-rates?currency=\(currency)")!
    }

    /// The decodable shape of a Coinbase exchange-rates payload.
    ///
    /// Shape: `{"data":{"currency":"BTC","rates":{"USD":"62537.68",...}}}`.
    /// Rate values are STRINGS.
    struct Payload: Decodable, Sendable {
        let currency: String
        let rates: [String: String]

        private enum TopKeys: String, CodingKey {
            case data
        }

        private enum DataKeys: String, CodingKey {
            case currency
            case rates
        }

        init(from decoder: Decoder) throws {
            let top = try decoder.container(keyedBy: TopKeys.self)
            let data = try top.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
            self.currency = try data.decode(String.self, forKey: .currency)
            self.rates = try data.decode([String: String].self, forKey: .rates)
        }
    }

    /// Pure decode: parse raw `Data` into `(currency, usdPerUnit)` WITHOUT
    /// inversion. Exposed for testing without network access.
    static func decode(_ data: Data) throws -> (currency: String, usdPerUnit: Double) {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let usdString = payload.rates["USD"], let usd = Double(usdString) else {
            throw RatesProviderError.malformedPayload
        }
        return (payload.currency.uppercased(), usd)
    }

    func fetchUSDPerUnit(for codes: Set<String>) async throws -> [String: Double] {
        // Only query crypto codes we know about that were requested (or all if
        // the caller didn't specify a relevant subset).
        let requested = codes.intersection(Set(cryptoCodes))
        let toFetch = requested.isEmpty ? cryptoCodes : Array(requested)

        var result: [String: Double] = [:]
        for code in toFetch {
            let data = try await fetchData(for: code)
            let decoded = try Self.decode(data)
            result[decoded.currency] = decoded.usdPerUnit
        }
        return result
    }

    private func fetchData(for currency: String) async throws -> Data {
        let (data, response) = try await session.data(from: Self.url(for: currency))
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw RatesProviderError.badResponse
        }
        return data
    }
}
