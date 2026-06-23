import SwiftUI

/// Applies the app's appearance / accent / reduce-transparency settings to a
/// SwiftUI root and injects the resolved ``Theme`` into the environment.
///
/// Usage: `someRoot.themedRoot(settings: settings)`. It:
/// - forces `.preferredColorScheme` for light/dark (`nil` for auto),
/// - applies the accent via `.tint`,
/// - reads the *effective* `colorScheme` (so `.auto` picks the right tokens),
/// - resolves a `Theme` and puts it in `\.theme`.
///
/// Keeping `NSApp.appearance` in sync (so AppKit status-item labels match) is
/// done separately by ``AppearanceSync`` from `AppDelegate`, since that affects
/// AppKit chrome outside any SwiftUI tree.
private struct ThemedRootModifier: ViewModifier {
    let settings: AppSettings
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        // For .auto, fall back to the system's effective scheme.
        let effective = settings.appearance.preferredColorScheme ?? systemScheme
        let theme = Theme.resolved(
            scheme: effective,
            reduceTransparency: settings.reduceTransparency
        )
        content
            .environment(\.theme, theme)
            .tint(settings.accent.color)
            .preferredColorScheme(settings.appearance.preferredColorScheme)
    }
}

extension View {
    /// Apply appearance + accent + resolved theme tokens to a root view.
    func themedRoot(settings: AppSettings) -> some View {
        modifier(ThemedRootModifier(settings: settings))
    }
}

// MARK: - Panel surface

/// The popover / panel background: a translucent material with the theme tint
/// layered on top, or a solid fill when reduce-transparency is on. This is the
/// SwiftUI-side fallback; the popover additionally hosts an `NSVisualEffectView`
/// for true vibrancy (see `PopoverController`).
struct PanelBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        if theme.reduceTransparency {
            theme.panelSolid
        } else {
            // Material approximates `backdrop-filter: saturate(180%) blur(30px)`;
            // the tint nudges it toward the prototype's panel rgba.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(theme.panelTint)
        }
    }
}

// MARK: - AppKit appearance sync

/// Keeps `NSApp.appearance` aligned with the user's appearance preference so the
/// AppKit-hosted status-item labels and popover chrome match the SwiftUI tree.
///
/// `AppDelegate` creates one and calls `apply()` once at boot; settings UI calls
/// it again whenever the preference changes.
@MainActor
enum AppearanceSync {
    static func apply(_ appearance: AppAppearance) {
        if let name = appearance.nsAppearanceName {
            NSApp.appearance = NSAppearance(named: name)
        } else {
            NSApp.appearance = nil // follow the system
        }
    }
}
