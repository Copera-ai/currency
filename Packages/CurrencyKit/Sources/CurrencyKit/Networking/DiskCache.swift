import Foundation

/// A tiny file cache for immutable payloads (dated fiat snapshots) and the last
/// good rates. Lives in `~/Library/Caches/ai.copera.currency` by default.
public struct DiskCache: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's Caches directory.
    public static func standard() -> DiskCache {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return DiskCache(directory: caches.appending(path: "ai.copera.currency", directoryHint: .isDirectory))
    }

    func read(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appending(path: name))
    }

    func write(_ data: Data, to name: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appending(path: name), options: .atomic)
        } catch {
            Log.persistence.error("Cache write \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Last good rates

    private static let lastRatesName = "last-rates.json"

    /// The most recent successful snapshot, for instant display at launch.
    public func loadLastRates() -> RatesSnapshot? {
        guard let data = read(Self.lastRatesName) else { return nil }
        return try? JSONDecoder().decode(RatesSnapshot.self, from: data)
    }

    public func saveLastRates(_ snapshot: RatesSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        write(data, to: Self.lastRatesName)
    }
}
