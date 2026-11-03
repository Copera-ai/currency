import AppKit
import Observation
import Sparkle

/// Sparkle updates (feed and EdDSA key come from Info.plist; see project.yml).
///
/// The updater only starts when `SUFeedURL` / `SUPublicEDKey` are real values, so a
/// misconfigured build hides "Check for Updates…" instead of failing at runtime.
///
/// Scheduled checks use gentle reminders (recommended for menu bar apps): Sparkle only
/// shows its window itself when it can be in immediate focus (e.g. right after launch);
/// otherwise ``availableUpdateVersion`` is set and the popover and status item menu
/// offer the update until the user looks at it.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private let driverDelegate: UserDriverDelegate

    /// Mirrors Sparkle's preference so SwiftUI toggles update when it changes.
    var automaticallyChecksForUpdates: Bool {
        didSet {
            guard automaticallyChecksForUpdates != oldValue else { return }
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// A version found by a scheduled check that the user has not looked at yet.
    private(set) var availableUpdateVersion: String?

    init(bundle: Bundle = .main) {
        let driverDelegate = UserDriverDelegate()
        let controller = Self.isConfigured(bundle: bundle)
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: driverDelegate)
            : nil
        self.driverDelegate = driverDelegate
        self.controller = controller
        automaticallyChecksForUpdates = controller?.updater.automaticallyChecksForUpdates ?? false
        if controller == nil {
            Log.app.info("Sparkle disabled: SUFeedURL/SUPublicEDKey missing")
        }
        driverDelegate.updater = self
    }

    var isAvailable: Bool { controller != nil }

    /// Checks now, or brings a pending (gently reminded) update into focus.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    static func isConfigured(bundle: Bundle) -> Bool {
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https",
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty
        else { return false }
        return true
    }

    // MARK: - Gentle reminders

    fileprivate func willShowUpdate(_ update: SUAppcastItem, handledBySparkle: Bool) {
        if handledBySparkle {
            // Sparkle's window is about to appear: bring the (menu bar only) app forward
            // so it doesn't open behind other apps. WindowCoordinator returns the app to
            // `.accessory` when the window closes.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        } else {
            availableUpdateVersion = update.displayVersionString
            Log.app.info("update \(update.displayVersionString, privacy: .public) available (gentle reminder)")
        }
    }

    fileprivate func clearReminder() {
        availableUpdateVersion = nil
    }
}

/// Sparkle's user driver delegate (an `NSObject`), forwarding to ``Updater``.
/// Sparkle calls it on the main thread.
@MainActor
private final class UserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    weak var updater: Updater?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Let Sparkle show scheduled updates only when it can do so in immediate focus;
    /// otherwise remind the user in the popover and menu instead of a window behind
    /// other apps.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        updater?.willShowUpdate(update, handledBySparkle: handleShowingUpdate)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updater?.clearReminder()
    }

    func standardUserDriverWillFinishUpdateSession() {
        updater?.clearReminder()
    }
}
