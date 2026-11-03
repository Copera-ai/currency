import SwiftUI

/// Menu bar app: AppKit status items + popover (see ``AppDelegate``) and a SwiftUI
/// Settings scene. `LSUIElement` keeps it out of the Dock until Settings opens.
@main
struct CoperaCurrencyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.model)
                .environment(appDelegate.model.store)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Copera Currency") { appDelegate.model.openSettings(.about) }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { appDelegate.model.checkForUpdates() }
                    .disabled(!appDelegate.model.updater.isAvailable)
            }
        }
    }
}
