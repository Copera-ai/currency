import CurrencyKit
import SwiftUI

/// Tracked pairs: a scrolling list of rows that expand inline into a chart.
struct PairsSection: View {
    /// About five rows; more room while a row shows its chart.
    static let maxListHeight: CGFloat = 300
    static let maxExpandedListHeight: CGFloat = 480

    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentHeight: CGFloat = 0
    @State private var selectedID: CurrencyPair.ID?
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tracking")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.pairs.isEmpty {
                    Text("24h")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 18)

            if store.pairs.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.pairs) { tracked in
                        PairRow(
                            tracked: tracked,
                            isExpanded: model.expandedPairID == tracked.id,
                            isSelected: listFocused && selectedID == tracked.id
                        ) {
                            toggle(tracked.id)
                        }
                        .id(tracked.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(max(contentHeight, 1), model.expandedPairID == nil ? Self.maxListHeight : Self.maxExpandedListHeight))
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(.downArrow) { moveSelection(1, proxy: proxy) }
            .onKeyPress(.upArrow) { moveSelection(-1, proxy: proxy) }
            .onKeyPress(.return) { toggleSelected() }
            .onKeyPress(.space) { toggleSelected() }
            .onChange(of: model.expandedPairID) { _, id in
                guard let id else { return }
                withMotion(reduceMotion) { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 3) {
                Text("No pairs yet").font(.system(size: 13, weight: .semibold))
                Text("Track a currency pair to see its rate and chart here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Add Pair…") { model.addPairFromAnywhere() }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
    }

    private func toggle(_ id: CurrencyPair.ID) {
        selectedID = id
        withMotion(reduceMotion) {
            model.expandedPairID = model.expandedPairID == id ? nil : id
        }
    }

    private func moveSelection(_ delta: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        let ids = store.pairs.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let current = selectedID.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        let next = ids[min(max(current + delta, 0), ids.count - 1)]
        selectedID = next
        proxy.scrollTo(next)
        return .handled
    }

    private func toggleSelected() -> KeyPress.Result {
        guard let selectedID else { return .ignored }
        toggle(selectedID)
        return .handled
    }
}

// MARK: - Row

struct PairRow: View {
    let tracked: TrackedPair
    let isExpanded: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store
    @State private var isHovered = false

    private var pair: CurrencyPair { tracked.pair }

    var body: some View {
        let quote = store.quote(for: pair)
        VStack(spacing: 0) {
            Button(action: onTap) {
                summary(quote)
            }
            .buttonStyle(.plain)

            if isExpanded {
                PairDetailView(tracked: tracked)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundStyle)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 1.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovered = $0 }
        .contextMenu { PairContextMenu(tracked: tracked) }
        .accessibilityElement(children: .contain)
    }

    private var backgroundStyle: AnyShapeStyle {
        if isExpanded { return AnyShapeStyle(.fill.tertiary) }
        if isHovered { return AnyShapeStyle(.fill.quaternary) }
        return AnyShapeStyle(.clear)
    }

    private func summary(_ quote: PairQuote?) -> some View {
        let base = model.currency(pair.base)
        let quoteCurrency = model.currency(pair.quote)
        return HStack(spacing: 10) {
            PairBadge(base: base, quote: quoteCurrency, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(pair.id)
                        .font(.system(size: 13, weight: .semibold))
                    if tracked.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                    if tracked.showInMenuBar {
                        Image(systemName: "menubar.rectangle")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .help("Shown in the menu bar")
                            .accessibilityLabel("In menu bar")
                    }
                }
                Text(base?.name ?? pair.base)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            Sparkline(pair: pair)
                .frame(width: 56, height: 22)
                .opacity(isExpanded ? 0 : 1)

            VStack(alignment: .trailing, spacing: 3) {
                Text(store.formatter.string(from: quote?.price))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .lineLimit(1)
                ChangePill(change: quote?.change24h, formatter: store.formatter)
            }
            .frame(minWidth: 72, alignment: .trailing)
            .redacted(reason: quote == nil && store.snapshot == nil ? .placeholder : [])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(quote))
        .accessibilityHint(isExpanded ? "Collapses the chart" : "Shows the chart")
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityText(_ quote: PairQuote?) -> String {
        var text = "\(pair.base) to \(pair.quote), \(store.formatter.string(from: quote?.price))"
        if quote?.change24h != nil { text += ", " + ChangePill.spoken(quote?.change24h, formatter: store.formatter) }
        if tracked.isFavorite { text += ", favorite" }
        return text
    }
}

/// Per-pair actions (row context menu).
struct PairContextMenu: View {
    let tracked: TrackedPair

    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store

    var body: some View {
        Toggle("Show in Menu Bar", isOn: Binding(
            get: { tracked.showInMenuBar },
            set: { store.setShowInMenuBar(tracked.id, $0) }
        ))
        Toggle("Favorite", isOn: Binding(
            get: { tracked.isFavorite },
            set: { store.setFavorite(tracked.id, $0) }
        ))
        Divider()
        Button("Copy Rate") { model.copyRate(of: tracked.pair) }
            .disabled(store.quote(for: tracked.pair) == nil)
        Button("Use in Converter") { model.useInConverter(tracked.pair) }
        Divider()
        Button("Remove", role: .destructive) {
            if model.expandedPairID == tracked.id { model.expandedPairID = nil }
            store.removePair(tracked.id)
        }
    }
}
