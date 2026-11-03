import Foundation

/// Reads the `UserDefaults` written by the pre-CurrencyKit app (PersistenceStore and
/// AppSettings, keys under `com.copera.currency.`).
enum LegacyMigration {
    static let namespace = "com.copera.currency."

    enum Key {
        static let pairs = namespace + "pairs"
        static let refreshInterval = namespace + "refreshInterval"
        static let menuBarFormat = namespace + "menuBarFormat"
        static let showChangeInMenuBar = namespace + "showChangeInMenuBar"
        static let appearance = namespace + "appearance"
        static let accent = namespace + "accent"
        static let reduceTransparency = namespace + "reduceTransparency"

        static let all = [pairs, refreshInterval, menuBarFormat, showChangeInMenuBar, appearance, accent, reduceTransparency]
    }

    /// The legacy pair record (JSON array stored as `Data` under ``Key/pairs``).
    struct LegacyPair: Decodable {
        let id: Int
        let base: String
        let quote: String
        let isFavorite: Bool
        let isTracked: Bool
        let sortOrder: Int
    }

    /// Builds a state from legacy defaults, or `nil` when none of the legacy keys exist.
    static func state(from defaults: UserDefaults) -> PersistedState? {
        guard Key.all.contains(where: { defaults.object(forKey: $0) != nil }) else { return nil }
        var state = PersistedState.initial

        if let data = defaults.data(forKey: Key.pairs),
           let legacy = try? JSONDecoder().decode([LegacyPair].self, from: data) {
            state.pairs = pairs(from: legacy)
        }

        var settings = UserSettings()
        if let seconds = defaults.object(forKey: Key.refreshInterval) as? Int {
            settings.refreshInterval = RefreshInterval(rawValue: seconds) ?? .nearest(toSeconds: seconds)
        }
        if let raw = defaults.string(forKey: Key.menuBarFormat) {
            // The old "plain" format is the new "value" format.
            settings.menuBarLabelFormat = raw == "plain" ? .value : MenuBarLabelFormat(rawValue: raw) ?? .pair
        }
        if defaults.object(forKey: Key.showChangeInMenuBar) != nil {
            settings.showChangeArrow = defaults.bool(forKey: Key.showChangeInMenuBar)
        }
        if let raw = defaults.string(forKey: Key.appearance), let value = AppearancePreference(rawValue: raw) {
            settings.appearance = value
        }
        if let raw = defaults.string(forKey: Key.accent), let value = AccentChoice(storedValue: raw) {
            settings.accent = value
        }
        settings.reduceTransparency = defaults.bool(forKey: Key.reduceTransparency)
        state.settings = settings
        return state
    }

    /// Keeps every legacy pair in the order the old list showed it (favorites first,
    /// then `sortOrder`). The old `isTracked` flag meant "show in menu bar".
    static func pairs(from legacy: [LegacyPair]) -> [TrackedPair] {
        let ordered = legacy.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return (lhs.sortOrder, lhs.id) < (rhs.sortOrder, rhs.id)
        }
        var seen: Set<CurrencyPair> = []
        return ordered.compactMap { item in
            let pair = CurrencyPair(base: item.base, quote: item.quote)
            guard pair.base != pair.quote, seen.insert(pair).inserted else { return nil }
            return TrackedPair(pair, isFavorite: item.isFavorite, showInMenuBar: item.isTracked)
        }
    }
}
