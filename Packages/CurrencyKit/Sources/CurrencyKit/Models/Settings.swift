import Foundation

/// How often rates refresh automatically.
public enum RefreshInterval: Int, Codable, CaseIterable, Sendable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600

    public var id: Int { rawValue }

    public var duration: Duration { .seconds(rawValue) }

    public var displayName: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        }
    }

    /// The closest supported interval to an arbitrary number of seconds (used by migration).
    public static func nearest(toSeconds seconds: Int) -> RefreshInterval {
        allCases.min { abs($0.rawValue - seconds) < abs($1.rawValue - seconds) } ?? .fiveMinutes
    }
}

/// What a menu-bar item shows before the rate.
public enum MenuBarLabelFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    /// `USD/BRL 5.44`
    case pair
    /// `R$ 5.44` (quote currency symbol)
    case symbol
    /// `5.44`
    case value
    /// `🇺🇸 5.44` (base flag; crypto falls back to its symbol)
    case flag

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pair: "Pair"
        case .symbol: "Symbol"
        case .value: "Value"
        case .flag: "Flag"
        }
    }
}

/// How many fraction digits rates show.
public enum DecimalsPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 2 digits for values ≥ 1, 4 below 1, 4 significant digits below 0.01.
    case automatic
    /// Two extra digits everywhere (FX-style `5.4406`).
    case precise

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .precise: "Precise"
        }
    }
}

/// Light / dark / follow the system.
public enum AppearancePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case light
    case dark
    case auto

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .auto: "Auto"
        }
    }
}

/// App accent color choices. The UI maps these to concrete colors via ``hex``.
public enum AccentChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    /// "Copera Emerald", the brand accent (the app's asset-catalog AccentColor).
    case emerald
    case copper
    case blue
    case pink
    case purple
    case red

    public var id: String { rawValue }

    /// `#RRGGBB` (light appearance; emerald is `#2CC98F` in dark).
    public var hex: String {
        switch self {
        case .emerald: "#0B8A5F"
        case .copper: "#D97757"
        case .blue: "#2A6FDB"
        case .pink: "#D6407F"
        case .purple: "#7C5CFF"
        case .red: "#E0322A"
        }
    }

    public var displayName: String { rawValue.capitalized }

    /// Parses a persisted raw value. Retired choices map to their replacement:
    /// "green" (near-identical to emerald) decodes as ``emerald``.
    public init?(storedValue raw: String) {
        if raw == "green" {
            self = .emerald
        } else {
            self.init(rawValue: raw)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = AccentChoice(storedValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown accent '\(raw)'")
        }
        self = value
    }
}

/// User preferences. Decoding tolerates missing keys so new settings can be added
/// without a schema bump.
public struct UserSettings: Codable, Hashable, Sendable {
    public var refreshInterval: RefreshInterval = .fiveMinutes
    public var menuBarLabelFormat: MenuBarLabelFormat = .pair
    public var showChangeArrow: Bool = true
    public var decimals: DecimalsPreference = .automatic
    public var appearance: AppearancePreference = .auto
    public var accent: AccentChoice = .emerald
    public var reduceTransparency: Bool = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserSettings()
        refreshInterval = (try? container.decodeIfPresent(RefreshInterval.self, forKey: .refreshInterval)) ?? defaults.refreshInterval
        menuBarLabelFormat = (try? container.decodeIfPresent(MenuBarLabelFormat.self, forKey: .menuBarLabelFormat)) ?? defaults.menuBarLabelFormat
        showChangeArrow = (try? container.decodeIfPresent(Bool.self, forKey: .showChangeArrow)) ?? defaults.showChangeArrow
        decimals = (try? container.decodeIfPresent(DecimalsPreference.self, forKey: .decimals)) ?? defaults.decimals
        appearance = (try? container.decodeIfPresent(AppearancePreference.self, forKey: .appearance)) ?? defaults.appearance
        accent = (try? container.decodeIfPresent(AccentChoice.self, forKey: .accent)) ?? defaults.accent
        reduceTransparency = (try? container.decodeIfPresent(Bool.self, forKey: .reduceTransparency)) ?? defaults.reduceTransparency
    }
}

/// Converter inputs, persisted across launches.
public struct ConverterState: Codable, Hashable, Sendable {
    public var from: String
    public var to: String
    /// Amount of `from` to convert.
    public var amount: Double

    public init(from: String = "USD", to: String = "BRL", amount: Double = 100) {
        self.from = from.uppercased()
        self.to = to.uppercased()
        self.amount = amount
    }

    /// The same inputs with `from` and `to` swapped.
    public var swapped: ConverterState { ConverterState(from: to, to: from, amount: amount) }
}
