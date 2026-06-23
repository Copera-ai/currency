import SwiftUI

/// The compact SwiftUI label rendered inside a single status-item button.
///
/// It reads the `@Observable` ``RatesStore`` and ``AppSettings`` directly, so it
/// auto-updates whenever the rate, change, format, or show-change toggle changes
/// — the AppKit ``MenuBarController`` never has to push value updates.
///
/// Layout: an optional format prefix, the formatted rate in tabular monospaced
/// digits, and (when enabled and non-flat) a small colored trend arrow.
struct StatusItemLabelView: View {
    let pair: CurrencyPair
    let store: RatesStore
    let settings: AppSettings

    /// Font used for the whole label (monospaced so digits don't jitter on tick).
    private static let font = Font.system(size: 12, design: .monospaced)

    var body: some View {
        let prefix = settings.menuBarFormat.prefix(for: pair)
        let rateText = store.fmt(store.rate(pair))
        let trend = Trend(change: store.change(pair))

        HStack(spacing: 4) {
            if !prefix.isEmpty {
                Text(prefix)
                    .font(Self.font)
            }

            Text(rateText)
                .font(Self.font)
                .monospacedDigit()

            if settings.showChangeInMenuBar, let arrow = trend.arrow {
                Text(arrow)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(trend == .up ? Color.green : Color.red)
            }
        }
        .padding(.horizontal, 6)
        .fixedSize()
    }
}
