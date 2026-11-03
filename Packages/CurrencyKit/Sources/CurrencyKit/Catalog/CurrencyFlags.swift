import Foundation

/// Flag emoji for fiat currencies.
public enum CurrencyFlags {
    /// Currencies whose code does not start with the issuing region, or that are
    /// shared by several regions.
    static let overrides: [String: String] = [
        "EUR": "🇪🇺",
        "ANG": "🇨🇼",
        "XCG": "🇨🇼",
        "XPF": "🇵🇫",
        "XCD": "🇦🇬",
        "XAF": "🇨🇲",
        "XOF": "🇸🇳",
    ]

    private static let isoRegions: Set<String> = Set(Locale.Region.isoRegions.map(\.identifier))
    private static let isoCurrencies: Set<String> = Set(Locale.commonISOCurrencyCodes)

    /// The flag for an ISO 4217 code, derived from its first two letters (the ISO
    /// 3166 region) unless overridden. `nil` when no region applies.
    public static func flag(forCurrencyCode code: String) -> String? {
        let code = code.uppercased()
        if let flag = overrides[code] { return flag }
        // Only real ISO 4217 codes: "BTC" must not become Bhutan's flag.
        guard code.count == 3, isoCurrencies.contains(code) else { return nil }
        let region = String(code.prefix(2))
        guard isoRegions.contains(region) else { return nil }
        return flag(forRegion: region)
    }

    /// Regional-indicator emoji for a two-letter region code, e.g. `"BR"` → 🇧🇷.
    public static func flag(forRegion region: String) -> String? {
        let base: UInt32 = 0x1F1E6 - 65 // "A"
        var scalars = String.UnicodeScalarView()
        for scalar in region.uppercased().unicodeScalars {
            guard (65...90).contains(scalar.value), let indicator = Unicode.Scalar(base + scalar.value) else { return nil }
            scalars.append(indicator)
        }
        return scalars.count == 2 ? String(scalars) : nil
    }
}
