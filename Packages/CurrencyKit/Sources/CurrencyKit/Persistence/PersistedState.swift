import Foundation

/// Everything the user configured, saved as one versioned JSON document.
public struct PersistedState: Codable, Hashable, Sendable {
    /// Bump when the shape changes incompatibly, and add a migration in ``StateStore``.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Tracked pairs in display order.
    public var pairs: [TrackedPair]
    public var settings: UserSettings
    public var converter: ConverterState

    public init(
        pairs: [TrackedPair] = TrackedPair.defaults,
        settings: UserSettings = UserSettings(),
        converter: ConverterState = ConverterState()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.pairs = pairs
        self.settings = settings
        self.converter = converter
    }

    /// First-launch state.
    public static let initial = PersistedState()
}
