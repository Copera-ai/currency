import AppKit
import CurrencyKit
import SwiftUI

/// Amount in → converted result out, with currency pickers and a swap button.
struct ConverterCard: View {
    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var amountText = ""
    @State private var isInvalid = false
    @State private var swapTurns = 0.0
    @State private var copied = false
    @State private var selection: TextSelection?
    @FocusState private var amountFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            fromRow
                .padding(.bottom, 16)
            divider
            toRow
                .padding(.top, 16)
        }
        .padding(14)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .onAppear { syncText(force: true) }
        .onChange(of: store.converter.amount) { syncText(force: false) }
        .onChange(of: model.amountFocusRequest) { amountFocused = true }
        .onChange(of: model.isPopoverShown) { _, shown in
            if shown { syncText(force: true) }
        }
        .background {
            Button("Copy Result") { copyResult() }
                .keyboardShortcut("c", modifiers: .command)
                // A text selection in the amount field keeps the standard Copy.
                .disabled(hasTextSelection)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: Rows

    private var fromRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            caption("From")
            HStack(alignment: .center, spacing: 10) {
                TextField("0", text: $amountText, selection: $selection)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isInvalid ? Color.red : Color.primary)
                    .focused($amountFocused)
                    .autocorrectionDisabled()
                    .writingToolsBehavior(.disabled)
                    .onChange(of: amountText) { _, text in amountChanged(text) }
                    .onSubmit(commitAmount)
                    .accessibilityLabel("Amount in \(store.converter.from)")
                CurrencyButton(side: .from)
            }
            if let hint = expressionHint {
                Text(hint)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    private var toRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            caption("To")
            HStack(alignment: .center, spacing: 10) {
                Button(action: copyResult) {
                    ZStack(alignment: .leading) {
                        Text(resultText)
                            .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                            .redacted(reason: store.converterResult == nil && store.snapshot == nil ? .placeholder : [])
                            .opacity(copied ? 0 : 1)
                        if copied {
                            Label("Copied", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tint)
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to copy (⌘C)")
                .accessibilityLabel("Result: \(resultText) \(store.converter.to). Copy")
                CurrencyButton(side: .to)
            }
            Text(rateLine)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .motion(reduceMotion, value: store.converterResult)
    }

    /// Hairline with the swap button centered on it.
    private var divider: some View {
        ZStack {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
            Button {
                withMotion(reduceMotion) {
                    swapTurns += 1
                    store.swapConverterCurrencies()
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(swapTurns * 180))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .help("Swap currencies")
            .accessibilityLabel("Swap currencies")
        }
        .frame(height: 0.5)
        .zIndex(1)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    // MARK: Values

    private var hasTextSelection: Bool {
        guard amountFocused, let selection else { return false }
        switch selection.indices {
        case .selection(let range): return !range.isEmpty
        case .multiSelection(let ranges): return !ranges.isEmpty
        @unknown default: return false
        }
    }

    private var resultText: String {
        store.formatter.string(from: store.converterResult)
    }

    private var rateLine: String {
        let from = store.converter.from
        let to = store.converter.to
        guard let rate = store.convert(1, from: from, to: to) else { return "1 \(from) = — \(to)" }
        return "1 \(from) = \(store.formatter.string(from: rate)) \(to)"
    }

    /// `= 1,250.00` under an arithmetic expression such as `1000 * 1.25`.
    private var expressionHint: String? {
        let operators = CharacterSet(charactersIn: "+*/×÷()")
        let hasMinusOperator = amountText.dropFirst().contains("-")
        guard amountText.rangeOfCharacter(from: operators) != nil || hasMinusOperator,
              let value = store.amountParser.parse(amountText) else { return nil }
        return "= " + store.formatter.string(from: value)
    }

    /// An empty field means 0 (the result follows, nothing stale is restored later).
    private func amountChanged(_ text: String) {
        isInvalid = !store.setConverterAmount(text: text)
    }

    /// Return replaces an expression with its value.
    private func commitAmount() {
        guard store.amountParser.parse(amountText) != nil else { return }
        syncText(force: true)
    }

    private func syncText(force: Bool) {
        // Don't rewrite what the user is typing unless it no longer matches the amount.
        let typed = amountText.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : store.amountParser.parse(amountText)
        if !force, amountFocused, typed == store.converter.amount { return }
        amountText = store.amountParser.editableString(store.converter.amount)
        isInvalid = false
    }

    /// Copies the plain, ungrouped full-precision value (`1234.56789`), not the display text.
    private func copyResult() {
        guard let text = store.formatter.plainString(from: store.converterResult) else { return }
        model.copy(text)
        withMotion(reduceMotion) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            withMotion(reduceMotion) { copied = false }
        }
    }
}

// MARK: - Currency button

/// Flag/badge + code; opens the searchable currency picker.
struct CurrencyButton: View {
    let side: ConverterSide

    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store

    var body: some View {
        let code = side == .from ? store.converter.from : store.converter.to
        Button {
            model.pickerSide = side
        } label: {
            HStack(spacing: 6) {
                CurrencyBadge(currency: model.currency(code), size: 20)
                Text(code)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.glass)
        .tint(nil)
        .help(model.currency(code)?.name ?? code)
        .accessibilityLabel("\(side == .from ? "From" : "To") currency: \(model.currency(code)?.name ?? code)")
        .popover(isPresented: Binding(
            get: { model.pickerSide == side },
            set: { if !$0, model.pickerSide == side { model.pickerSide = nil } }
        ), arrowEdge: .bottom) {
            CurrencyPicker(selected: code, suggested: suggestedCodes) { currency in
                if side == .from {
                    store.converter.from = currency.code
                } else {
                    store.converter.to = currency.code
                }
                model.pickerSide = nil
            }
        }
    }

    /// Currencies from tracked pairs, shown first.
    private var suggestedCodes: [String] {
        var seen = Set<String>()
        return store.pairs.flatMap { [$0.pair.base, $0.pair.quote] }.filter { seen.insert($0).inserted }
    }
}
