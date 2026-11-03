import Foundation
import ServiceManagement

/// "Launch at login" via `SMAppService.mainApp`.
///
/// The user can also change this in System Settings → General → Login Items, so the
/// status is always re-read rather than cached.
@MainActor
public enum LoginItemManager {
    /// Whether the app is registered to launch at login.
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether macOS is waiting for the user to approve the login item.
    public static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters the app as a login item.
    ///
    /// - Throws: the `SMAppService` error (e.g. unsigned dev builds). Re-read
    ///   ``isEnabled`` afterwards to reflect the real state.
    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
