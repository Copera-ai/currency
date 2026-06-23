import SwiftUI

/// The real popover content: header + converter card + tracking list + footer.
///
/// Width is fixed at ``PopoverController/width`` (368); height is intrinsic. The
/// panel chrome (material/solid background, corner radius, shadow) is applied by
/// the hosting `NSVisualEffectView` + this view's background; the popIn animation
/// runs on appear.
///
/// `onOpenSettings` opens the Settings window and closes the popover (the popover
/// can't reach `SettingsWindowController` directly — it's threaded in from
/// `AppDelegate` via `PopoverController`).
struct PopoverView: View {
    let store: RatesStore
    let settings: AppSettings
    /// Opens Settings at an optional target tab (`nil` = last-viewed tab).
    let onOpenSettings: (SettingsTab?) -> Void

    @Environment(\.theme) private var theme

    // Converter state. Default USD → BRL per the design.
    @State private var from: Currency = Currency.byCode["USD"] ?? Currency.supported[0]
    @State private var to: Currency = Currency.byCode["BRL"] ?? Currency.supported[1]
    @State private var amountText: String = "100"

    // In-popover active-row emphasis (no longer "chooses" the menu-bar item).
    @State private var activePairID: Int?

    // popIn animation.
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            header
            converterCard
            sectionSeparator
            tracking
            sectionSeparator
            footer
        }
        .frame(width: PopoverController.width)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(theme.panelBorder, lineWidth: hairline)
        )
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97, anchor: .top)
        .offset(y: appeared ? 0 : -8)
        .onAppear {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.16)) {
                appeared = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Exchange Rates")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(theme.text)
                // Live "Updated Ns ago" — re-evaluated every second.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(store.relativeUpdatedLabel())
                        .font(.system(size: 11))
                        .foregroundStyle(theme.text2)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                CircularIconButton("arrow.clockwise", label: "Refresh") {
                    Task { await store.refresh() }
                }
                CircularIconButton("gearshape", label: "Settings") {
                    onOpenSettings(nil)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Converter

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var resultText: String {
        store.fmt(store.convert(amount: amount, from: from.code, to: to.code))
    }

    private var converterCard: some View {
        VStack(spacing: 0) {
            // FROM
            converterBlock(label: "FROM", chip: from) {
                cycle(isFrom: true)
            } valueField: {
                TextField("", text: $amountText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 23, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Swap divider (line + accent button to the right)
            HStack(spacing: 10) {
                Rectangle().fill(theme.sep).frame(height: hairline)
                SwapButton { swap() }
            }
            .padding(.vertical, 9)

            // TO
            converterBlock(label: "TO", chip: to) {
                cycle(isFrom: false)
            } valueField: {
                Text(resultText)
                    .font(.system(size: 23, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.fieldBg))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.fieldBorder, lineWidth: hairline))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func converterBlock<Value: View>(
        label: String,
        chip: Currency,
        cycleAction: @escaping () -> Void,
        @ViewBuilder valueField: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.text2)
            HStack(spacing: 10) {
                valueField()
                CurrencyChip(currency: chip, action: cycleAction)
            }
        }
    }

    // MARK: - Tracking

    private var tracking: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TRACKING")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(theme.text2)
                Spacer()
                Button("Manage") { onOpenSettings(.currencies) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 7)

            if store.trackedSorted.isEmpty {
                emptyOrLoading
            } else {
                ForEach(store.trackedSorted) { pair in
                    PairRow(
                        pair: pair,
                        rateText: store.fmt(store.rate(pair)),
                        change: store.change(pair),
                        isActive: activePairID == pair.id,
                        baseCurrency: Currency.byCode[pair.base],
                        onTap: { activePairID = pair.id },
                        onToggleFavorite: { store.toggleFavorite(pair.id) }
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 11)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var emptyOrLoading: some View {
        let loading = store.loadState == .loading && store.lastUpdated == nil
        Text(loading ? "Loading rates…" : "No tracked pairs")
            .font(.system(size: 12))
            .foregroundStyle(theme.text2)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            FooterButton(title: "Settings…") { onOpenSettings(nil) }
            Spacer()
            FooterButton(title: "Quit Copera Currency") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 11)
    }

    // MARK: - Helpers

    private var sectionSeparator: some View {
        Rectangle()
            .fill(theme.sep)
            .frame(height: hairline)
            .padding(.horizontal, 14)
    }

    /// Advance the currency on one side, skipping the other side's currency so
    /// both sides never match.
    private func cycle(isFrom: Bool) {
        let current = isFrom ? from : to
        let other = isFrom ? to : from
        let list = Currency.supported
        guard let start = list.firstIndex(of: current) else { return }
        for step in 1...list.count {
            let candidate = list[(start + step) % list.count]
            if candidate != other {
                if isFrom { from = candidate } else { to = candidate }
                return
            }
        }
    }

    private func swap() {
        let oldFrom = from
        from = to
        to = oldFrom
    }
}

/// A footer text button that dims when idle and brightens on hover.
private struct FooterButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(hovering ? theme.text : theme.text2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
