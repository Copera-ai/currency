import SwiftUI

/// General settings: refresh interval, the menu-bar-pairs reconciliation row,
/// "Show change in menu bar", and "Launch at login".
struct SettingsGeneralTab: View {
    let store: RatesStore
    @Bindable var settings: AppSettings

    /// Deep-link to the Currencies tab (the "Manage in Currencies" button).
    let openCurrencies: () -> Void

    @Environment(\.theme) private var theme

    /// Mirrors the real `SMAppService` status; re-read on appear and after toggles.
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Refresh interval — native menu picker over the RefreshInterval cases.
            SettingRow(
                title: "Refresh interval",
                subtitle: "How often rates update automatically"
            ) {
                Picker("", selection: refreshBinding) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            // Reconciliation row: the prototype's single "Menu bar pair" picker is
            // replaced — every tracked pair now gets its own menu-bar item.
            SettingRow(
                title: "Menu bar pairs",
                subtitle: "Each tracked pair gets its own menu bar item — manage them in Currencies"
            ) {
                Button("Manage in Currencies", action: openCurrencies)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            SettingRow(
                title: "Show change in menu bar",
                subtitle: "Display the 24h trend arrow"
            ) {
                AppToggle(isOn: $settings.showChangeInMenuBar)
            }

            SettingRow(
                title: "Launch at login",
                subtitle: "Open Copera Currency when you sign in",
                showSeparator: false
            ) {
                AppToggle(isOn: launchBinding)
            }
        }
        .alert(
            "Couldn’t update Login Items",
            isPresented: Binding(
                get: { loginError != nil },
                set: { if !$0 { loginError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { loginError = nil }
        } message: {
            Text(loginError ?? "")
        }
    }

    // MARK: Bindings

    private var refreshBinding: Binding<RefreshInterval> {
        Binding(
            get: { store.refreshInterval },
            set: { store.refreshInterval = $0 }
        )
    }

    /// Drives the real login-item registration and re-reads the resulting status
    /// so the toggle always reflects the system's truth (even on failure).
    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LoginItemManager.setEnabled(newValue)
                } catch {
                    loginError = error.localizedDescription
                }
                launchAtLogin = LoginItemManager.isEnabled
            }
        )
    }
}
