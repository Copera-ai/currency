import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppModel.self) private var model

    private static let repository = URL(string: "https://github.com/Copera-ai/currency")!
    private static let currencyAPI = URL(string: "https://github.com/fawazahmed0/exchange-api")!
    private static let coinbase = URL(string: "https://www.coinbase.com")!

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .accessibilityHidden(true)
                    VStack(spacing: 3) {
                        Text("Copera Currency")
                            .font(.system(size: 22, weight: .bold))
                        Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("Live exchange rates and crypto prices, a glance away in your menu bar.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 320)
                    HStack(spacing: 8) {
                        if model.updater.isAvailable {
                            Button("Check for Updates…") { model.checkForUpdates() }
                                .buttonStyle(.glassProminent)
                        }
                        Link(destination: Self.repository) {
                            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                LabeledContent {
                    Link("Coinbase", destination: Self.coinbase)
                } label: {
                    Text("Live rates")
                    Text("Real-time fiat exchange rates, crypto prices and crypto history")
                }
                LabeledContent {
                    Link("currency-api", destination: Self.currencyAPI)
                } label: {
                    Text("Daily rates")
                    Text("Fawaz Ahmed's free currency API: fiat history and fallback rates")
                }
            } header: {
                Text("Data Sources")
            } footer: {
                Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .frame(height: 500)
    }
}
