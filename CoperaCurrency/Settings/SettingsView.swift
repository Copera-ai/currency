import CurrencyKit
import SwiftUI

/// Settings window (⌘,): toolbar tabs, each a grouped form.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView()
            }
            Tab("Currencies", systemImage: "dollarsign.arrow.circlepath", value: SettingsTab.currencies) {
                CurrenciesSettingsView()
            }
            Tab("Appearance", systemImage: "paintpalette", value: SettingsTab.appearance) {
                AppearanceSettingsView()
            }
            Tab("About", systemImage: "info.circle", value: SettingsTab.about) {
                AboutSettingsView()
            }
        }
        .frame(width: 540)
        .tint(store.settings.accent.color)
    }
}
