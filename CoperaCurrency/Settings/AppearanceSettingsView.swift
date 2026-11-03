import CurrencyKit
import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(CurrencyStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Window") {
                Picker("Appearance", selection: $store.settings.appearance) {
                    ForEach([AppearancePreference.auto, .light, .dark]) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Accent color") {
                    AccentSwatches(selection: $store.settings.accent)
                }
                Toggle("Reduce transparency", isOn: $store.settings.reduceTransparency)
            }

            Section {
                MenuBarPreview()
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                Picker("Label", selection: $store.settings.menuBarLabelFormat) {
                    ForEach(MenuBarLabelFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show change arrow", isOn: $store.settings.showChangeArrow)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Choose which pairs appear in the menu bar in Currencies.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Decimals", selection: $store.settings.decimals) {
                    ForEach(DecimalsPreference.allCases) { decimals in
                        Text(decimals.displayName).tag(decimals)
                    }
                }
            } footer: {
                Text(decimalsExample)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }

    private var decimalsExample: String {
        let sample = store.pairs.first.flatMap { store.quote(for: $0.pair) }
        let value = sample?.price ?? 5.4406
        let automatic = RateFormatter(locale: store.formatter.locale, decimals: .automatic).string(from: value)
        let precise = RateFormatter(locale: store.formatter.locale, decimals: .precise).string(from: value)
        return "Automatic shows \(automatic), Precise shows \(precise)."
    }
}

/// Round color swatches; the selected one gets a ring.
private struct AccentSwatches: View {
    @Binding var selection: AccentChoice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentChoice.allCases) { choice in
                Button {
                    withMotion(reduceMotion) { selection = choice }
                } label: {
                    Circle()
                        .fill(choice.color.gradient)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if selection == choice {
                                Circle().fill(.white).frame(width: 6, height: 6)
                            }
                        }
                        .padding(3)
                        .overlay {
                            Circle()
                                .strokeBorder(selection == choice ? choice.color : .clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .help(choice == .emerald ? "Emerald (default)" : choice.displayName)
                .accessibilityLabel(choice.displayName)
                .accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
        }
    }
}

/// A miniature menu bar showing the labels exactly as configured.
private struct MenuBarPreview: View {
    @Environment(CurrencyStore.self) private var store

    var body: some View {
        let pairs = Array((store.menuBarPairs.isEmpty ? Array(store.pairs.prefix(1)) : store.menuBarPairs).prefix(2))
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: "#22B07E"), Color(hex: "#0A3F4A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                ForEach(pairs) { tracked in
                    label(store.menuBarLabel(for: tracked.pair))
                        .fixedSize()
                }
                Image(systemName: "wifi")
                Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .fixedSize()
            }
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .frame(height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Menu bar preview: " + pairs.map { store.menuBarLabel(for: $0.pair).text }.joined(separator: ", "))
    }

    private func label(_ label: MenuBarLabel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !label.prefix.isEmpty {
                Text(label.prefix)
            }
            Text(label.value)
                .fontWeight(.medium)
                .monospacedDigit()
            if label.showsArrow, let arrow = label.trend.arrow {
                Text(arrow)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(label.trend.color)
                    .baselineOffset(1.5)
            }
        }
        .contentTransition(.numericText())
    }
}
