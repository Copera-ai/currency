import CurrencyKit
import SwiftUI

/// Tracked pairs: reorder by dragging, show in the menu bar, favorite, add and remove.
struct CurrenciesSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store

    @State private var selection: Set<CurrencyPair.ID> = []

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                VStack(spacing: 0) {
                    pairList
                    Divider()
                    bottomBar
                }
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Tracked Pairs")
            } footer: {
                Text("Drag to reorder; menu bar items follow this order. Reordering here resets positions set by ⌘-dragging items in the menu bar.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 470)
        .sheet(isPresented: $model.isAddingPair) {
            AddPairSheet()
        }
    }

    private var pairList: some View {
        List(selection: $selection) {
            ForEach(store.pairs) { tracked in
                PairSettingsRow(tracked: tracked)
                    .tag(tracked.id)
                    .contextMenu { PairContextMenu(tracked: tracked) }
            }
            .onMove { store.movePairs(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.enabled)
        .frame(height: 300)
        .onDeleteCommand(perform: removeSelected)
        .overlay {
            if store.pairs.isEmpty {
                ContentUnavailableView {
                    Label("No Pairs", systemImage: "dollarsign.arrow.circlepath")
                } description: {
                    Text("Add a pair to track its rate.")
                } actions: {
                    Button("Add Pair…") { model.isAddingPair = true }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                model.isAddingPair = true
            } label: {
                Image(systemName: "plus").frame(width: 24, height: 22)
            }
            .help("Add a pair")
            .accessibilityLabel("Add pair")
            Divider().frame(height: 16)
            Button(action: removeSelected) {
                Image(systemName: "minus").frame(width: 24, height: 22)
            }
            .disabled(selection.isEmpty)
            .help("Remove the selected pairs")
            .accessibilityLabel("Remove selected pairs")
            Spacer()
            Text("\(store.pairs.count) pairs · \(store.menuBarPairs.count) in menu bar")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing, 10)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private func removeSelected() {
        for id in selection { store.removePair(id) }
        selection = []
    }
}

private struct PairSettingsRow: View {
    let tracked: TrackedPair

    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store

    var body: some View {
        let pair = tracked.pair
        let base = model.currency(pair.base)
        let quote = model.currency(pair.quote)
        HStack(spacing: 10) {
            PairBadge(base: base, quote: quote, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(pair.id).font(.system(size: 13, weight: .semibold))
                Text("\(base?.name ?? pair.base) → \(quote?.name ?? pair.quote)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(store.formatter.string(from: store.quote(for: pair)?.price))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                store.toggleFavorite(tracked.id)
            } label: {
                Image(systemName: tracked.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(tracked.isFavorite ? Color.yellow : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(tracked.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(tracked.isFavorite ? "Remove \(pair.id) from Favorites" : "Add \(pair.id) to Favorites")
            Toggle("Show in menu bar", isOn: Binding(
                get: { tracked.showInMenuBar },
                set: { store.setShowInMenuBar(tracked.id, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help("Show in menu bar")
            .accessibilityLabel("Show \(pair.id) in menu bar")
        }
        .padding(.vertical, 3)
    }
}
