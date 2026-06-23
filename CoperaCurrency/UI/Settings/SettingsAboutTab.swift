import AppKit
import SwiftUI

/// About settings: app icon, name, version, tagline, and a (placeholder)
/// "Check for Updates…" button.
struct SettingsAboutTab: View {
    @Environment(\.theme) private var theme

    @State private var showUpdatePlaceholder = false

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            appIcon
                .padding(.top, 34)

            Text("Copera Currency")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(theme.text)
                .padding(.top, 16)

            Text(versionString)
                .font(.system(size: 12))
                .foregroundStyle(theme.text2)
                .padding(.top, 3)

            Text("Real-time currency and crypto rates, always a glance away in your menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 320)
                .padding(.top, 18)

            Button("Check for Updates…") { showUpdatePlaceholder = true }
                .buttonStyle(CheckForUpdatesButtonStyle())
                .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        // TODO(Phase 6): wire to Sparkle UpdaterManager.
        .alert("Automatic Updates Coming Soon", isPresented: $showUpdatePlaceholder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Built-in update checking arrives in a later version of Copera Currency.")
        }
    }

    /// Real app icon if available, else an accent-tinted "$" placeholder matching
    /// the prototype until a real icon ships.
    @ViewBuilder
    private var appIcon: some View {
        if let image = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 15))
        } else {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.accentColor)
                .frame(width: 58, height: 58)
                .overlay(
                    Text("$")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(.white)
                )
        }
    }
}

/// The bordered, field-filled "Check for Updates…" button matching the design.
private struct CheckForUpdatesButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? theme.hover : theme.fieldBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme.fieldBorder, lineWidth: hairline)
            )
    }
}
