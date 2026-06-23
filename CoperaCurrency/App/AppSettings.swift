import Foundation
import Observation

/// User-facing app settings, backed by `UserDefaults` and observable by the UI.
///
/// Keys are namespaced under `com.copera.currency.` (matching ``PersistenceStore``).
/// Each property persists on `didSet`. Phase 2 ships the menu-bar-relevant
/// settings; later phases extend this with appearance / accent / reduce-
/// transparency / launch-at-login. The design intentionally keeps each setting a
/// simple computed-default + persisted property so new ones drop in uniformly.
/// UserDefaults keys for ``AppSettings``, namespaced like ``PersistenceStore``.
/// Declared at file scope (not nested in the `@MainActor` class) so its static
/// defaults are evaluated nonisolated.
private enum SettingsKey {
    static let menuBarFormat = PersistenceStore.namespace + "menuBarFormat"
    static let showChangeInMenuBar = PersistenceStore.namespace + "showChangeInMenuBar"
    static let appearance = PersistenceStore.namespace + "appearance"
    static let accent = PersistenceStore.namespace + "accent"
    static let reduceTransparency = PersistenceStore.namespace + "reduceTransparency"
}

@MainActor
@Observable
final class AppSettings {
    /// Backing store. `UserDefaults.standard` is thread-safe and used on main.
    private let defaults: UserDefaults

    /// How each menu-bar item renders its pair (default `.pair`).
    var menuBarFormat: LabelFormat {
        didSet { defaults.set(menuBarFormat.rawValue, forKey: SettingsKey.menuBarFormat) }
    }

    /// Whether to show the colored trend arrow next to each menu-bar rate.
    var showChangeInMenuBar: Bool {
        didSet { defaults.set(showChangeInMenuBar, forKey: SettingsKey.showChangeInMenuBar) }
    }

    /// Light / Dark / Auto appearance preference (default `.auto`).
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: SettingsKey.appearance) }
    }

    /// The app-wide accent color (default `.copper`, the design's `#D97757`).
    var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: SettingsKey.accent) }
    }

    /// When on, panels use a solid fill instead of a translucent material.
    var reduceTransparency: Bool {
        didSet { defaults.set(reduceTransparency, forKey: SettingsKey.reduceTransparency) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.string(forKey: SettingsKey.menuBarFormat),
           let format = LabelFormat(rawValue: raw) {
            self.menuBarFormat = format
        } else {
            self.menuBarFormat = .pair
        }

        if defaults.object(forKey: SettingsKey.showChangeInMenuBar) != nil {
            self.showChangeInMenuBar = defaults.bool(forKey: SettingsKey.showChangeInMenuBar)
        } else {
            self.showChangeInMenuBar = true
        }

        if let raw = defaults.string(forKey: SettingsKey.appearance),
           let value = AppAppearance(rawValue: raw) {
            self.appearance = value
        } else {
            self.appearance = .auto
        }

        if let raw = defaults.string(forKey: SettingsKey.accent),
           let value = AccentChoice(rawValue: raw) {
            self.accent = value
        } else {
            self.accent = .copper
        }

        self.reduceTransparency = defaults.bool(forKey: SettingsKey.reduceTransparency) // default false
    }
}
