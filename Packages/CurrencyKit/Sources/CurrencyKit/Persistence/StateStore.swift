import Foundation

/// Loads and saves ``PersistedState`` as `state.json` in Application Support.
///
/// - First launch: migrates the legacy `UserDefaults` once, otherwise seeds defaults.
/// - Unreadable file: moves it aside as `state.corrupt-<timestamp>.json` before
///   starting fresh, so user data is never silently overwritten.
public struct StateStore: Sendable {
    /// How ``load()`` obtained the state.
    public enum LoadOutcome: Equatable, Sendable {
        /// Read the existing file.
        case loaded
        /// No file and nothing to migrate; defaults were seeded.
        case seededDefaults
        /// No file; state was migrated from the legacy `UserDefaults`.
        case migratedFromLegacy
        /// The file was unreadable and defaults are in use. `backup` is where the old
        /// file was moved; `nil` if moving it failed (the file was then left untouched).
        case recoveredFromCorruptFile(backup: URL?)
    }

    public static let fileName = "state.json"

    public let directory: URL
    /// Suite holding the legacy settings; `nil` means `UserDefaults.standard`.
    private let legacySuiteName: String?
    private let migratesLegacyDefaults: Bool

    /// - Parameters:
    ///   - directory: where `state.json` lives.
    ///   - legacySuiteName: `UserDefaults` suite of the pre-CurrencyKit app (`nil` = standard).
    ///   - migratesLegacyDefaults: set `false` to skip the legacy import entirely.
    public init(directory: URL, legacySuiteName: String? = nil, migratesLegacyDefaults: Bool = true) {
        self.directory = directory
        self.legacySuiteName = legacySuiteName
        self.migratesLegacyDefaults = migratesLegacyDefaults
    }

    /// `~/Library/Application Support/ai.copera.currency`.
    public static func standard() -> StateStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return StateStore(directory: support.appending(path: "ai.copera.currency", directoryHint: .isDirectory))
    }

    public var fileURL: URL { directory.appending(path: Self.fileName) }

    /// Loads the state, migrating or recovering as needed. Never throws: any problem
    /// results in a usable state plus an outcome describing what happened.
    public func load() -> (state: PersistedState, outcome: LoadOutcome) {
        guard let data = try? Data(contentsOf: fileURL) else {
            if migratesLegacyDefaults, let legacy = LegacyMigration.state(from: legacyDefaults) {
                Log.persistence.info("Migrated legacy UserDefaults into \(Self.fileName, privacy: .public)")
                saveLogging(legacy)
                return (legacy, .migratedFromLegacy)
            }
            saveLogging(.initial)
            return (.initial, .seededDefaults)
        }

        do {
            return (try decode(data), .loaded)
        } catch {
            Log.persistence.error("Unreadable \(Self.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
            // Only write a fresh file once the old one is safely out of the way.
            let backup = backupCorruptFile()
            if backup != nil { saveLogging(.initial) }
            return (.initial, .recoveredFromCorruptFile(backup: backup))
        }
    }

    /// Atomically writes `state`.
    public func save(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }

    // MARK: - Private

    private var legacyDefaults: UserDefaults {
        legacySuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private func decode(_ data: Data) throws -> PersistedState {
        let header = try JSONDecoder().decode(Header.self, from: data)
        switch header.schemaVersion {
        case PersistedState.currentSchemaVersion:
            var state = try JSONDecoder().decode(PersistedState.self, from: data)
            state.pairs = Self.deduplicated(state.pairs)
            return state
        default:
            // Newer (downgrade) or unknown versions are not understood; keep the file aside.
            throw CurrencyKitError.decoding("Unsupported schemaVersion \(header.schemaVersion)")
        }
    }

    private static func deduplicated(_ pairs: [TrackedPair]) -> [TrackedPair] {
        var seen: Set<CurrencyPair> = []
        return pairs.filter { $0.pair.base != $0.pair.quote && seen.insert($0.pair).inserted }
    }

    private func backupCorruptFile() -> URL? {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateTimeSeparator(.standard))
            .replacingOccurrences(of: ":", with: "")
        let backup = directory.appending(path: "state.corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
            Log.persistence.notice("Moved unreadable state to \(backup.lastPathComponent, privacy: .public)")
            return backup
        } catch {
            Log.persistence.fault("Could not back up unreadable state: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func saveLogging(_ state: PersistedState) {
        do {
            try save(state)
        } catch {
            Log.persistence.error("Saving state failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
