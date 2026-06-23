import SwiftUI

/// Currencies settings: search, a reorderable list of pairs (favorite, badge,
/// name·kind, rate, and a per-row "Show in menu bar" toggle = tracked), plus an
/// "Add currency pair" sheet.
struct SettingsCurrenciesTab: View {
    let store: RatesStore
    let settings: AppSettings

    @Environment(\.theme) private var theme
    @State private var search = ""
    @State private var showAddSheet = false

    /// The pairs to display, filtered by the search query (code / name / pair).
    private var visiblePairs: [CurrencyPair] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return store.pairs }
        return store.pairs.filter { pair in
            let base = Currency.byCode[pair.base]
            let quote = Currency.byCode[pair.quote]
            let haystack = [
                pair.base, pair.quote, "\(pair.base)/\(pair.quote)",
                base?.name ?? "", quote?.name ?? "",
            ].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    /// Reordering only makes sense when the full, unfiltered list is shown.
    private var canReorder: Bool {
        search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(placeholder: "Search currencies", text: $search)
                .padding(.top, 12)
                .padding(.bottom, 4)

            pairList

            Button { showAddSheet = true } label: {
                Text("+ Add currency pair")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(theme.fieldBorder, style: StrokeStyle(lineWidth: hairline, dash: [4, 3]))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .sheet(isPresented: $showAddSheet) {
            // Re-apply the theme: a sheet presents in its own tree, so it does not
            // inherit `.tint` / `.preferredColorScheme` from the window root.
            AddPairSheet(store: store)
                .themedRoot(settings: settings)
        }
    }

    // Extracted so the type checker doesn't choke on the nested closures/ternary.
    private var pairList: some View {
        let reorder = canReorder
        let onMove: ((IndexSet, Int) -> Void)? = reorder
            ? { source, destination in performMove(from: source, to: destination) }
            : nil
        return List {
            ForEach(visiblePairs) { pair in
                CurrencyPairRow(store: store, pair: pair)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    /// Map a `List` move (over the visible/full order) back onto the store.
    private func performMove(from source: IndexSet, to destination: Int) {
        var ids = visiblePairs.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        store.reorder(ids)
    }
}

// MARK: - Row

/// A single currency-pair row in the Currencies list.
private struct CurrencyPairRow: View {
    let store: RatesStore
    let pair: CurrencyPair

    @Environment(\.theme) private var theme

    private var base: Currency? { Currency.byCode[pair.base] }
    private var kindTag: String { (base?.kind == .crypto) ? "Crypto" : "FX" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text2)

                FavoriteStar(isFavorite: pair.isFavorite) {
                    store.toggleFavorite(pair.id)
                }

                SymbolBadge(currency: base, size: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(pair.base)/\(pair.quote)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("\(base?.name ?? pair.base) · \(kindTag)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.text2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(store.fmt(store.rate(pair)))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)

                // Per-row "Show in menu bar" == isTracked (smaller 36×21 toggle).
                AppToggle(
                    isOn: Binding(
                        get: { pair.isTracked },
                        set: { _ in store.toggleTracked(pair.id) }
                    ),
                    width: 36,
                    height: 21
                )
                .accessibilityLabel("Show \(pair.base)/\(pair.quote) in menu bar")
            }
            .padding(.vertical, 9)

            Rectangle().fill(theme.sep).frame(height: hairline)
        }
        .contentShape(Rectangle())
    }
}
