import AppKit
import CurrencyKit
import SwiftUI

extension Color {
    /// `#RRGGBB` → color (sRGB). Malformed input yields gray.
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// Positive change: "Copera Emerald", independent of the user's accent choice.
    static let trendUp = Color("AccentColor")
    /// Negative change.
    static let trendDown = Color(nsColor: .systemRed)
}

extension NSColor {
    convenience init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self.init(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            return
        }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Menu-bar counterpart of ``Color/trendUp``.
    static let trendUp = NSColor(named: "AccentColor") ?? .systemGreen
}

extension AccentChoice {
    /// The tint for this choice. Emerald is the asset-catalog AccentColor (light/dark variants).
    var color: Color {
        self == .emerald ? Color("AccentColor") : Color(hex: hex)
    }
}

extension Trend {
    var color: Color {
        switch self {
        case .up: .trendUp
        case .down: .trendDown
        case .flat: .secondary
        }
    }

    var nsColor: NSColor {
        switch self {
        case .up: .trendUp
        case .down: .systemRed
        case .flat: .secondaryLabelColor
        }
    }
}

extension AppearancePreference {
    /// `nil` follows the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .auto: nil
        }
    }

    /// Settings label ("System" reads better than "Auto" next to Light/Dark).
    var label: String {
        self == .auto ? "System" : displayName
    }
}

// MARK: - Motion

extension Animation {
    /// The app's standard motion: fast and lightly sprung.
    static let ui = Animation.spring(duration: 0.3, bounce: 0.18)
}

/// `withAnimation` that degrades to a short fade when Reduce Motion is on.
@MainActor
func withMotion<Result>(_ reduceMotion: Bool, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .ui, body)
}

extension View {
    /// `.animation(.ui, value:)` honoring Reduce Motion.
    func motion<V: Equatable>(_ reduceMotion: Bool, value: V) -> some View {
        animation(reduceMotion ? .easeInOut(duration: 0.12) : .ui, value: value)
    }
}
