import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` (macOS 13+) for the "Launch at login"
/// setting.
///
/// `SMAppService.mainApp` registers the app itself as a login item — no separate
/// helper target or entitlement is required. The user can also toggle the item
/// in System Settings → General → Login Items, so we always re-read `.status`
/// rather than caching the value.
@MainActor
enum LoginItemManager {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the app as a login item.
    ///
    /// - Throws: an `SMAppService` error if registration fails (e.g. the app is
    ///   unsigned / in an unexpected location during development). Callers should
    ///   surface this and re-read ``isEnabled`` to reflect the true state.
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            // `register()` is idempotent; calling it when already enabled is fine.
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
