import CurrencyKit
import SwiftUI

/// Pick two currencies, preview the live rate, add the pair.
struct AddPairSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var base = "USD"
    @State private var quote = "EUR"
    @State private var showInMenuBar = false
    @State private var picking: ConverterSide?
    @State private var swapTurns = 0.0
    @State private var failure: CurrencyStore.AddPairResult?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Pair").font(.title3.weight(.semibold))
                Text("Track a rate in the popover and, optionally, the menu bar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            HStack(spacing: 10) {
                currencyField(.from, code: base)
                Button {
                    withMotion(reduceMotion) {
                        swapTurns += 1
                        swap(&base, &quote)
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(swapTurns * 180))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Swap")
                .accessibilityLabel("Swap currencies")
                currencyField(.to, code: quote)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            preview
                .padding(.horizontal, 20)
                .padding(.top, 14)

            Toggle("Show in menu bar", isOn: $showInMenuBar)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            HStack {
                if let message = validationMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                    .tint(nil)
                Button("Add Pair", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(validationMessage != nil)
            }
            .padding(20)
            .motion(reduceMotion, value: validationMessage)
        }
        .frame(width: 440)
        .onChange(of: base) { failure = nil }
        .onChange(of: quote) { failure = nil }
    }

    private func currencyField(_ side: ConverterSide, code: String) -> some View {
        let currency = model.currency(code)
        return Button {
            picking = side
        } label: {
            HStack(spacing: 10) {
                CurrencyBadge(currency: currency, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(side == .from ? "BASE" : "QUOTE")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Text(code).font(.system(size: 15, weight: .semibold))
                    Text(currency?.name ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(side == .from ? "Base" : "Quote") currency: \(currency?.name ?? code)")
        .popover(isPresented: Binding(get: { picking == side }, set: { if !$0 { picking = nil } }), arrowEdge: .bottom) {
            CurrencyPicker(selected: code) { picked in
                if side == .from { base = picked.code } else { quote = picked.code }
                picking = nil
            }
        }
    }

    private var preview: some View {
        let rate = store.convert(1, from: base, to: quote)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("1 \(base) =")
                .foregroundStyle(.secondary)
            Text(store.formatter.string(from: rate))
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text(quote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .motion(reduceMotion, value: rate)
        .accessibilityElement(children: .combine)
    }

    private var validationMessage: String? {
        if base == quote { return message(for: .sameCurrency) }
        if store.pairs.contains(where: { $0.pair == CurrencyPair(base: base, quote: quote) }) { return message(for: .duplicate) }
        return failure.flatMap(message(for:))
    }

    private func message(for result: CurrencyStore.AddPairResult) -> String? {
        switch result {
        case .added: nil
        case .duplicate: "\(base)/\(quote) is already tracked."
        case .sameCurrency: "Pick two different currencies."
        case .unknownCurrency(let code): "\(code) isn't a supported currency."
        }
    }

    private func add() {
        let result = store.addPair(base: base, quote: quote, showInMenuBar: showInMenuBar)
        if result == .added {
            dismiss()
        } else {
            failure = result
        }
    }
}
