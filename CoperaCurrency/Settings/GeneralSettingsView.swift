import AppKit
import CurrencyKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store

    @State private var launchAtLogin = false
    @State private var loginRequiresApproval = false
    @State private var loginError: String?

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = model.updater
        Form {
            Section {
                Picker("Refresh rates every", selection: $store.settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                LabeledContent("Last updated") {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        HStack(spacing: 8) {
                            Text(store.updatedText(relativeTo: context.date).replacingOccurrences(of: "Updated ", with: "").capitalizedFirst)
                                .foregroundStyle(.secondary)
                            Button("Refresh Now") { model.refresh() }
                                .controlSize(.small)
                                .disabled(store.isRefreshing)
                        }
                    }
                }
            } header: {
                Text("Rates")
            } footer: {
                Text("Fiat and crypto rates are live from Coinbase.")
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginRequiresApproval {
                    LabeledContent {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Label("Waiting for your approval in System Settings.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section {
                KeyboardShortcuts.Recorder("Open converter", name: .openConverter)
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Press this shortcut anywhere to open Copera Currency with the amount field ready to type.")
                    .foregroundStyle(.secondary)
            }

            if model.updater.isAvailable {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                    LabeledContent("Version \(Bundle.main.shortVersion)") {
                        Button("Check Now") { model.checkForUpdates() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 548)
        .onAppear(perform: readLoginItemStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            readLoginItemStatus()
        }
    }

    /// The user can change this in System Settings at any time: always re-read.
    private func readLoginItemStatus() {
        launchAtLogin = LoginItemManager.isEnabled
        loginRequiresApproval = LoginItemManager.requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Couldn't \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
        readLoginItemStatus()
    }
}

extension String {
    /// "just now" → "Just now".
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
