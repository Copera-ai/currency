import SwiftUI

/// Entry point for the Copera Currency menu-bar app.
///
/// The app runs as a menu-bar-only agent (`LSUIElement = true`), so there is no
/// main window. All UI lifecycle is driven from ``AppDelegate``; the `Settings`
/// scene below exists only to give SwiftUI a valid (empty) scene graph. Real
/// settings UI ships in a later phase via an AppKit `NSWindowController`.
@main
struct CoperaCurrencyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
