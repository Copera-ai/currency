import SwiftUI

/// A sheet for adding a new tracked currency pair: Base + Quote pickers, a live
/// rate preview, and an "Add" button gated on a valid, non-duplicate pair.
struct AddPairSheet: View {
    let store: RatesStore

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var base = "USD"
    @State private var quote = "BRL"

    /// True when the chosen pair is invalid (same currency) or already exists.
    private var isDuplicate: Bool {
        store.pairs.contains { $0.base == base && $0.quote == quote }
    }
    private var isInvalid: Bool { base == quote }
    private var canAdd: Bool { !isInvalid && !isDuplicate }

    private var previewText: String {
        guard !isInvalid else { return "—" }
        return store.fmt(store.rate(base, quote))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Currency Pair")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.text)
                .padding(.bottom, 16)

            currencyPicker(title: "Base", selection: $base)
                .padding(.bottom, 12)
            currencyPicker(title: "Quote", selection: $quote)
                .padding(.bottom, 16)

            preview
                .padding(.bottom, 18)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(theme.settingsContent)
    }

    // MARK: Subviews

    private func currencyPicker(title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 56, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(Currency.supported, id: \.code) { currency in
                    Text("\(currency.code) — \(currency.name)").tag(currency.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        }
    }

    private var preview: some View {
        HStack(spacing: 10) {
            SymbolBadge(currency: Currency.byCode[base], size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(base)/\(quote)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(isInvalid ? "Pick two different currencies"
                     : (isDuplicate ? "Already added" : "Live preview"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text2)
            }
            Spacer()
            Text(previewText)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.fieldBg))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.fieldBorder, lineWidth: hairline))
    }

    // MARK: Actions

    private func add() {
        guard canAdd else { return }
        _ = store.addPair(base: base, quote: quote)
        dismiss()
    }
}
