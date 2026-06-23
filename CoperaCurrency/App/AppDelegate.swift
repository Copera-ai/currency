import AppKit
import SwiftUI

/// Boots the menu-bar app and owns the top-level AppKit objects.
///
/// Phase 0 wires up a single smoke-test `NSStatusItem` to prove the full stack
/// (LSUIElement + NSStatusItem + NSHostingView + SwiftUI + arm64 + Swift 6)
/// works end to end. Later phases replace this with the real
/// `MenuBarController` / `RatesStore` / `UpdaterManager`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Strong reference to the status item — without it, the item is released
    /// and silently disappears from the menu bar.
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: no Dock icon, no app menu focus stealing.
        NSApp.setActivationPolicy(.accessory)
        installSmokeTestStatusItem()
    }

    private func installSmokeTestStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        let hosting = NSHostingView(rootView: StatusItemSmokeLabel())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        statusItem = item
    }
}

/// Minimal compact label rendered inside the status-item button via NSHostingView.
private struct StatusItemSmokeLabel: View {
    var body: some View {
        Text("$ Copera")
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 6)
    }
}
