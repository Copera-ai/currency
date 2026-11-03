import CurrencyKit
import SwiftUI

/// Searchable list of every currency in the catalog, grouped into sections.
///
/// Type to filter by code or name; ↑/↓ move the highlight, Return picks it, Esc closes.
struct CurrencyPicker: View {
    let selected: String
    /// Codes listed first under "Your Currencies" (e.g. those in tracked pairs).
    var suggested: [String] = []
    let onSelect: (Currency) -> Void

    @State private var query = ""
    @State private var highlighted: String?
    @FocusState private var searchFocused: Bool

    private let catalog = CurrencyCatalog.shared

    private struct Section: Identifiable {
        let title: String
        let currencies: [Currency]
        var id: String { title }
    }

    var body: some View {
        let sections = self.sections
        let flat = sections.flatMap(\.currencies)
        VStack(spacing: 0) {
            searchField(flat: flat)
                .padding(10)
            Divider()
            if flat.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                list(sections)
            }
        }
        .frame(width: 300, height: 400)
        // Shown in a popover over other glass (the converter's rows): plain glass lets
        // their text show through, a thicker material keeps the list legible.
        .presentationBackground(.thickMaterial)
        .onAppear {
            highlighted = selected
            searchFocused = true
        }
        .onChange(of: query) {
            highlighted = flat.first?.code
        }
    }

    private func searchField(flat: [Currency]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search currencies", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    if let code = highlighted, let currency = catalog.currency(for: code) { onSelect(currency) }
                }
                .onKeyPress(.downArrow) { move(1, in: flat) }
                .onKeyPress(.upArrow) { move(-1, in: flat) }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func list(_ sections: [Section]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(sections) { section in
                        SwiftUI.Section {
                            ForEach(section.currencies) { currency in
                                row(currency)
                                    .id(rowID(section, currency))
                            }
                        } header: {
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .onChange(of: highlighted) { _, code in
                guard let code, let section = sections.first(where: { $0.currencies.contains { $0.code == code } }) else { return }
                proxy.scrollTo("\(section.id)-\(code)")
            }
            .onAppear {
                if let section = sections.first(where: { $0.currencies.contains { $0.code == selected } }) {
                    proxy.scrollTo("\(section.id)-\(selected)", anchor: .center)
                }
            }
        }
    }

    private func rowID(_ section: Section, _ currency: Currency) -> String {
        "\(section.id)-\(currency.code)"
    }

    private func row(_ currency: Currency) -> some View {
        let isHighlighted = highlighted == currency.code
        return Button {
            onSelect(currency)
        } label: {
            HStack(spacing: 10) {
                CurrencyBadge(currency: currency, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(currency.code)
                        .font(.system(size: 13, weight: .semibold))
                    Text(currency.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if currency.code == selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tint)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.tint.opacity(0.18))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = currency.code } }
        .accessibilityLabel("\(currency.name), \(currency.code)")
        .accessibilityAddTraits(currency.code == selected ? .isSelected : [])
    }

    // MARK: Data

    private var sections: [Section] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let results = catalog.search(trimmed)
            return [
                Section(title: "Currencies", currencies: results.filter { $0.kind == .fiat }),
                Section(title: "Crypto", currencies: results.filter { $0.kind == .crypto }),
            ].filter { !$0.currencies.isEmpty }
        }
        let yours = suggested.compactMap { catalog.currency(for: $0) }
        return [
            Section(title: "Your Currencies", currencies: yours),
            Section(title: "Crypto", currencies: catalog.crypto),
            Section(title: "All Currencies", currencies: catalog.fiat),
        ].filter { !$0.currencies.isEmpty }
    }

    private func move(_ delta: Int, in flat: [Currency]) -> KeyPress.Result {
        // The same currency can appear in two sections; navigate unique codes in order.
        var seen = Set<String>()
        let codes = flat.map(\.code).filter { seen.insert($0).inserted }
        guard !codes.isEmpty else { return .handled }
        let current = highlighted.flatMap { codes.firstIndex(of: $0) } ?? (delta > 0 ? -1 : codes.count)
        highlighted = codes[min(max(current + delta, 0), codes.count - 1)]
        return .handled
    }
}
