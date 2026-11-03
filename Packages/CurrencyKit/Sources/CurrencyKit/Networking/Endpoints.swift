import Foundation

/// Upstream URLs.
enum Endpoints {
    /// Hosts serving the fawazahmed0 currency API, in preference order.
    enum FiatHost: CaseIterable, Sendable {
        /// Cloudflare Pages (`max-age=0`, updates first).
        case pages
        /// jsDelivr mirror (fallback; can lag by a day).
        case jsdelivr
    }

    /// The first day with dated snapshots on the Pages host.
    static let earliestFiatDay = CalendarDay(year: 2024, month: 3, day: 2)

    static func fiatLatest(_ host: FiatHost) -> URL {
        switch host {
        case .pages: url("https://latest.currency-api.pages.dev/v1/currencies/usd.min.json")
        case .jsdelivr: url("https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json")
        }
    }

    static func fiatSnapshot(_ day: CalendarDay, _ host: FiatHost) -> URL {
        switch host {
        case .pages: url("https://\(day).currency-api.pages.dev/v1/currencies/usd.min.json")
        case .jsdelivr: url("https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@\(day)/v1/currencies/usd.min.json")
        }
    }

    static let currencyNames = url("https://latest.currency-api.pages.dev/v1/currencies.min.json")

    /// Batched ticker for several Coinbase products.
    static func coinbaseProducts(_ productIDs: [String]) -> URL {
        var components = URLComponents(string: "https://api.coinbase.com/api/v3/brokerage/market/products")
        components?.queryItems = productIDs.map { URLQueryItem(name: "product_ids", value: $0) }
        return components?.url ?? url("https://api.coinbase.com/api/v3/brokerage/market/products")
    }

    /// OHLC candles, newest first, at most 300 rows per request.
    static func coinbaseCandles(productID: String, granularity: Int, start: Date, end: Date) -> URL {
        let base = "https://api.exchange.coinbase.com/products/\(productID)/candles"
        var components = URLComponents(string: base)
        let iso = Date.ISO8601FormatStyle()
        components?.queryItems = [
            URLQueryItem(name: "granularity", value: String(granularity)),
            URLQueryItem(name: "start", value: start.formatted(iso)),
            URLQueryItem(name: "end", value: end.formatted(iso)),
        ]
        return components?.url ?? url(base)
    }

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else { preconditionFailure("Invalid URL literal: \(string)") }
        return url
    }
}
