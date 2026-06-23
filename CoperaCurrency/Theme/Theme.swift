import SwiftUI

// MARK: - Color(hex:)

extension Color {
    /// Build a `Color` from a packed `0xRRGGBB` value plus an optional alpha.
    ///
    /// Used throughout the theme so every token diffs 1:1 against the design
    /// prototype's hex/rgba literals (asset-catalog colors can't express the
    /// exact alphas + the reduce-transparency axis as cleanly).
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Appearance & accent choices

/// The user's appearance preference. `.auto` follows the system.
enum AppAppearance: String, CaseIterable, Sendable {
    case light
    case dark
    case auto

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .auto: return "Auto"
        }
    }

    /// The `colorScheme` to force, or `nil` for `.auto` (follow the system).
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }

    /// The matching `NSAppearance` to keep AppKit (status items, popover chrome)
    /// in sync, or `nil` for `.auto` (follow the system).
    var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .light: return .aqua
        case .dark: return .darkAqua
        case .auto: return nil
        }
    }
}

/// The five selectable accent colors (first is the default).
enum AccentChoice: String, CaseIterable, Sendable {
    case copper   // #D97757 (default)
    case blue     // #2A6FDB
    case green    // #1F8A5B
    case purple   // #7C5CFF
    case red      // #E0322A

    var color: Color {
        switch self {
        case .copper: return Color(hex: 0xD97757)
        case .blue:   return Color(hex: 0x2A6FDB)
        case .green:  return Color(hex: 0x1F8A5B)
        case .purple: return Color(hex: 0x7C5CFF)
        case .red:    return Color(hex: 0xE0322A)
        }
    }
}

// MARK: - Theme tokens

/// A fully-resolved set of design tokens for one effective color scheme +
/// reduce-transparency setting. Values replicate the prototype's `theme()`
/// function (see the design handoff); light and dark token sets are exact.
///
/// `Theme` carries only colors/metrics that depend on the resolved scheme; the
/// accent is applied app-wide via `.tint` and so is passed separately when a
/// component needs it directly.
struct Theme: Equatable {
    // Text
    var text: Color
    var text2: Color

    // Surfaces / chrome
    var panelSolid: Color          // solid panel fill (used when reduceTransparency)
    var panelTint: Color           // translucent tint layered over the material
    var panelBorder: Color
    var fieldBg: Color
    var fieldBorder: Color
    var sep: Color
    var hover: Color
    var menutext: Color

    // Settings chrome (built now for Phase 4)
    var settingsSidebar: Color
    var settingsContent: Color

    // Semantic
    var positive: Color
    var negative: Color
    var positivePillBg: Color
    var negativePillBg: Color

    // Shadow
    var shadowColor: Color
    var shadowRadius: CGFloat
    var shadowY: CGFloat

    /// Whether the material blur should be suppressed (reduce transparency).
    var reduceTransparency: Bool

    // MARK: Static brand / badge colors (scheme-independent)

    /// Bitcoin brand orange.
    static let btcBadge = Color(hex: 0xF7931A)
    /// Ethereum brand periwinkle.
    static let ethBadge = Color(hex: 0x627EEA)
    /// Neutral grey fill for fiat badges (`rgba(128,128,130,.16)`).
    static let fiatBadge = Color(hex: 0x808082, alpha: 0.16)

    // Settings nav badge colors (built now for Phase 4).
    static let navGeneral = Color(hex: 0x8E8E93)
    static let navCurrencies = Color(hex: 0x34C759)
    static let navAppearance = Color(hex: 0x5E5CE6)
    static let navAbout = Color(hex: 0x0A84FF)

    // MARK: Resolved token sets

    /// Resolve a `Theme` for the effective `scheme` and reduce-transparency flag.
    static func resolved(scheme: ColorScheme, reduceTransparency: Bool) -> Theme {
        scheme == .dark
            ? dark(reduceTransparency: reduceTransparency)
            : light(reduceTransparency: reduceTransparency)
    }

    private static func light(reduceTransparency rt: Bool) -> Theme {
        Theme(
            text: Color(hex: 0x1D1D1F),
            text2: Color(hex: 0x3C3C43, alpha: 0.6),
            panelSolid: Color(hex: 0xF4F4F6),
            panelTint: Color(hex: 0xF7F7F9, alpha: 0.72),
            panelBorder: Color(hex: 0x000000, alpha: 0.09),
            fieldBg: Color(hex: 0xFFFFFF, alpha: 0.75),
            fieldBorder: Color(hex: 0x000000, alpha: 0.10),
            sep: Color(hex: 0x000000, alpha: 0.08),
            hover: Color(hex: 0x000000, alpha: 0.05),
            menutext: Color(hex: 0x1D1D1F),
            settingsSidebar: Color(hex: 0xE7E7EA),
            settingsContent: Color(hex: 0xF6F6F8),
            positive: Color(hex: 0x1A8F4C),
            negative: Color(hex: 0xD23B32),
            positivePillBg: Color(hex: 0x28A55F, alpha: 0.14),
            negativePillBg: Color(hex: 0xD63C32, alpha: 0.14),
            shadowColor: Color(hex: 0x000000, alpha: 0.28),
            shadowRadius: 30,
            shadowY: 18,
            reduceTransparency: rt
        )
    }

    private static func dark(reduceTransparency rt: Bool) -> Theme {
        Theme(
            text: Color(hex: 0xF5F5F7),
            text2: Color(hex: 0xEBEBF5, alpha: 0.6),
            panelSolid: Color(hex: 0x242428),
            panelTint: Color(hex: 0x242428, alpha: 0.74),
            panelBorder: Color(hex: 0xFFFFFF, alpha: 0.10),
            fieldBg: Color(hex: 0xFFFFFF, alpha: 0.07),
            fieldBorder: Color(hex: 0xFFFFFF, alpha: 0.13),
            sep: Color(hex: 0xFFFFFF, alpha: 0.10),
            hover: Color(hex: 0xFFFFFF, alpha: 0.07),
            menutext: Color(hex: 0xFFFFFF),
            settingsSidebar: Color(hex: 0x242428),
            settingsContent: Color(hex: 0x1C1C20),
            positive: Color(hex: 0x30D158),
            negative: Color(hex: 0xFF453A),
            positivePillBg: Color(hex: 0x28A55F, alpha: 0.14),
            negativePillBg: Color(hex: 0xD63C32, alpha: 0.14),
            shadowColor: Color(hex: 0x000000, alpha: 0.6),
            shadowRadius: 30,
            shadowY: 18,
            reduceTransparency: rt
        )
    }
}

// MARK: - Badge resolution

extension Theme {
    /// The background/foreground a currency badge should use.
    /// Crypto get their brand colors + white text; fiat get a neutral grey.
    func badgeStyle(for currency: Currency?) -> (background: Color, foreground: Color) {
        switch currency?.kind {
        case .crypto:
            let bg: Color
            if let hex = currency?.badgeHex, let value = UInt(hex.dropFirst(), radix: 16) {
                bg = Color(hex: value)
            } else {
                bg = Theme.btcBadge
            }
            return (bg, .white)
        default:
            return (Theme.fiatBadge, text)
        }
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.resolved(scheme: .light, reduceTransparency: false)
}

extension EnvironmentValues {
    /// The resolved design tokens for the current view tree.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
