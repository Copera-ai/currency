import CurrencyKit
import SwiftUI

/// A round currency mark: a circular flag for fiat, a brand-colored coin for crypto,
/// or the symbol on a neutral disc when neither applies.
struct CurrencyBadge: View {
    let currency: Currency?
    var size: CGFloat = 24

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let flag = currency?.flag {
            // Flag emoji are rectangles with transparent padding: overscale, then clip.
            Text(flag)
                .font(.system(size: size * 1.32))
                .frame(width: size, height: size)
        } else if let currency, currency.kind == .crypto {
            ZStack {
                Circle().fill(Color(hex: currency.brandColorHex ?? "#8E8E93").gradient)
                glyph(for: currency).foregroundStyle(.white)
            }
        } else {
            ZStack {
                Circle().fill(.quaternary)
                glyph(for: currency).foregroundStyle(.primary)
            }
        }
    }

    private func glyph(for currency: Currency?) -> some View {
        let text = Self.glyphText(for: currency)
        let scale: CGFloat = switch text.count {
        case 1: 0.5
        case 2: 0.4
        case 3: 0.3
        default: 0.25
        }
        return Text(text)
            .font(.system(size: size * scale, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(size * 0.08)
    }

    static func glyphText(for currency: Currency?) -> String {
        guard let currency else { return "?" }
        return currency.symbol.count <= 2 ? currency.symbol : String(currency.code.prefix(4))
    }
}

/// Base badge with the quote badge tucked into its lower-right corner.
struct PairBadge: View {
    let base: Currency?
    let quote: Currency?
    var size: CGFloat = 30

    var body: some View {
        CurrencyBadge(currency: base, size: size)
            .overlay(alignment: .bottomTrailing) {
                CurrencyBadge(currency: quote, size: size * 0.52)
                    .background(Circle().fill(.background).padding(-1.5))
                    .offset(x: size * 0.16, y: size * 0.12)
            }
            .padding(.trailing, size * 0.16)
            .padding(.bottom, size * 0.12)
            .accessibilityHidden(true)
    }
}

/// Signed percentage on a tinted capsule.
struct ChangePill: View {
    let change: Double?
    let formatter: RateFormatter

    var body: some View {
        let trend = Trend(change: change)
        HStack(spacing: 2) {
            if change != nil, trend != .flat {
                Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .heavy))
            }
            Text(Self.magnitude(change, formatter: formatter))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(trend.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(trend.color.opacity(trend == .flat ? 0.1 : 0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(change, formatter: formatter))
    }

    /// `2.14%` without a sign (the arrow and color carry the direction).
    static func magnitude(_ change: Double?, formatter: RateFormatter) -> String {
        formatter.percent(change.map(abs)).replacingOccurrences(of: "+", with: "")
    }

    static func spoken(_ change: Double?, formatter: RateFormatter) -> String {
        guard let change else { return "Change unknown" }
        switch Trend(change: change) {
        case .up: return "Up \(magnitude(change, formatter: formatter)) in 24 hours"
        case .down: return "Down \(magnitude(change, formatter: formatter)) in 24 hours"
        case .flat: return "Unchanged in 24 hours"
        }
    }
}
