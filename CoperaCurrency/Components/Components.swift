import SwiftUI

// MARK: - Hairline

/// A 0.5pt-equivalent stroke width for the design's `0.5px` borders. SwiftUI
/// strokes in points; on Retina this renders as a true hairline.
let hairline: CGFloat = 0.5

// MARK: - CircularIconButton

/// A 28pt square icon button (r8) used in the popover header (refresh / gear).
/// Hover fills the `theme.hover` background.
struct CircularIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    init(_ systemName: String, label: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.accessibilityLabel = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hovering ? theme.hover : theme.fieldBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.fieldBorder, lineWidth: hairline)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - SwapButton

/// A 30pt circular button (accent glyph) that swaps the converter currencies.
struct SwapButton: View {
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(hovering ? theme.hover : theme.panelTint)
                )
                .overlay(Circle().strokeBorder(theme.fieldBorder, lineWidth: hairline))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Swap currencies")
    }
}

// MARK: - SymbolBadge

/// A circular badge showing a currency's symbol glyph. Crypto use their brand
/// background + white text; fiat use a neutral grey.
struct SymbolBadge: View {
    let currency: Currency?
    var size: CGFloat = 24

    @Environment(\.theme) private var theme

    var body: some View {
        let style = theme.badgeStyle(for: currency)
        Text(currency?.symbol ?? "?")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(style.foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(style.background))
    }
}

// MARK: - CurrencyChip

/// A tappable chip (badge + code + chevron) for the converter. Tap cycles the
/// currency (the caller skips the other side's currency).
struct CurrencyChip: View {
    let currency: Currency
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SymbolBadge(currency: currency, size: 20)
                Text(currency.code)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(theme.text2)
            }
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(hovering ? theme.hover : theme.panelTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(theme.fieldBorder, lineWidth: hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - ChangePill

/// A rounded pill showing a 24h change percentage with a ▲/▼ arrow, colored
/// green (≥0) or red (<0).
struct ChangePill: View {
    let change: Double

    @Environment(\.theme) private var theme

    var body: some View {
        let positive = change >= 0 || !change.isFinite
        let color = positive ? theme.positive : theme.negative
        let bg = positive ? theme.positivePillBg : theme.negativePillBg
        let arrow = positive ? "\u{25B2}" : "\u{25BC}"  // ▲ / ▼
        let value = change.isFinite ? abs(change) : 0

        Text("\(arrow) \(String(format: "%.2f", value))%")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6).fill(bg))
    }
}

// MARK: - FavoriteStar

/// A star toggle: filled accent when favorited, outline `text2` otherwise.
struct FavoriteStar: View {
    let isFavorite: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isFavorite ? Color.accentColor : theme.text2)
                .frame(width: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Unfavorite" : "Favorite")
    }
}

// MARK: - PairRow

/// A tracked-pair row: left accent bar (active) + star + badge + label column +
/// rate + change pill. Tapping the row sets the active emphasis (caller-owned).
struct PairRow: View {
    let pair: CurrencyPair
    let rateText: String
    let change: Double
    let isActive: Bool
    let baseCurrency: Currency?
    let onTap: () -> Void
    let onToggleFavorite: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Left accent bar marks the active pair.
            RoundedRectangle(cornerRadius: 2)
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 3, height: 22)

            FavoriteStar(isFavorite: pair.isFavorite, action: onToggleFavorite)

            SymbolBadge(currency: baseCurrency, size: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(pair.base)/\(pair.quote)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(baseCurrency?.name ?? pair.base)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(rateText)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                ChangePill(change: change)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(hovering ? theme.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
    }
}

// MARK: - AppToggle

/// A parameterized custom switch (40×23 for settings, 36×21 for currencies).
/// Accent track when on; knob slides with `easeInOut(0.18)`.
struct AppToggle: View {
    @Binding var isOn: Bool
    var width: CGFloat = 40
    var height: CGFloat = 23

    private var knobSize: CGFloat { height - 4 }
    private var travel: CGFloat { width - height }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? Color.accentColor : Color(hex: 0x787880, alpha: 0.32))
                    .frame(width: width, height: height)
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .offset(x: isOn ? travel + 2 : 2)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - SegmentedControl

/// A pill segmented control with an accent selection (used for Light/Dark/Auto
/// and menu-bar format in Settings).
struct SegmentedControl<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Color.white : theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.fieldBg))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.fieldBorder, lineWidth: hairline))
    }
}

// MARK: - AccentSwatch

/// A 26pt color circle; selected state shows a double-ring.
struct AccentSwatch: View {
    let choice: AccentChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(choice.color)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: isSelected ? 2 : 0)
                )
                .overlay(
                    Circle()
                        .strokeBorder(choice.color, lineWidth: isSelected ? 2 : 0)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - NavBadge

/// A ~22pt rounded-rect badge holding a white SF Symbol on a nav color
/// (Settings sidebar; built now for Phase 4).
struct NavBadge: View {
    let systemName: String
    let color: Color
    var selected: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.white.opacity(0.22) : color)
            )
    }
}

// MARK: - SettingRow

/// A titled settings row (title 13 + optional subtitle 11) with a trailing
/// control and a bottom separator. Built now for Phase 4.
struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var showSeparator: Bool = true
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.text2)
                    }
                }
                Spacer()
                trailing()
            }
            .padding(.vertical, 10)

            if showSeparator {
                Rectangle().fill(theme.sep).frame(height: hairline)
            }
        }
    }
}

// MARK: - SearchField

/// A search field with a magnifying-glass leading icon. Built now for Phase 4.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(theme.text2)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.fieldBg))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.fieldBorder, lineWidth: hairline))
    }
}
