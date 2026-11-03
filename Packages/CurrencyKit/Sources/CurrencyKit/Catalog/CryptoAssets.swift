import Foundation

/// The curated crypto assets the app offers.
///
/// Coinbase availability was verified against
/// `api.coinbase.com/api/v3/brokerage/market/products` (Nov 2026). USDC has no
/// `USDC-USD` product on Coinbase (it is the settlement unit), so it is priced from
/// the daily currency API instead.
enum CryptoAssets {
    static let all: [Currency] = [
        asset("BTC", "Bitcoin", "₿", "#F7931A"),
        asset("ETH", "Ethereum", "Ξ", "#627EEA"),
        asset("USDT", "Tether", "₮", "#26A17B"),
        asset("XRP", "XRP", "XRP", "#23292F"),
        asset("BNB", "BNB", "BNB", "#F3BA2F"),
        asset("SOL", "Solana", "◎", "#9945FF"),
        asset("USDC", "USD Coin", "USDC", "#2775CA", onCoinbase: false),
        asset("DOGE", "Dogecoin", "Ð", "#C2A633"),
        asset("ADA", "Cardano", "₳", "#0033AD"),
        asset("LINK", "Chainlink", "LINK", "#2A5ADA"),
        asset("XLM", "Stellar", "XLM", "#14B6E7"),
        asset("BCH", "Bitcoin Cash", "BCH", "#8DC351"),
        asset("AVAX", "Avalanche", "AVAX", "#E84142"),
        asset("LTC", "Litecoin", "Ł", "#345D9D"),
        asset("SHIB", "Shiba Inu", "SHIB", "#FFA409"),
        asset("DOT", "Polkadot", "DOT", "#E6007A"),
        asset("UNI", "Uniswap", "UNI", "#FF007A"),
        asset("POL", "Polygon", "POL", "#8247E5"),
        asset("ATOM", "Cosmos", "ATOM", "#6F7390"),
    ]

    private static func asset(_ code: String, _ name: String, _ symbol: String, _ hex: String, onCoinbase: Bool = true) -> Currency {
        Currency(
            code: code,
            name: name,
            symbol: symbol,
            kind: .crypto,
            brandColorHex: hex,
            coinbaseProductID: onCoinbase ? "\(code)-USD" : nil
        )
    }
}
