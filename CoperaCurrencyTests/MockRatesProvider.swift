import Foundation
@testable import CoperaCurrency

/// A `Sendable` test double for `RatesProvider`.
///
/// Either returns a fixed map, or throws when `shouldThrow` is set.
struct MockRatesProvider: RatesProvider {
    let map: [String: Double]
    let shouldThrow: Bool

    init(map: [String: Double] = [:], shouldThrow: Bool = false) {
        self.map = map
        self.shouldThrow = shouldThrow
    }

    struct MockError: Error {}

    func fetchUSDPerUnit(for codes: Set<String>) async throws -> [String: Double] {
        if shouldThrow { throw MockError() }
        return map
    }
}

enum TestSupport {
    /// A fresh, isolated UserDefaults suite for a single test.
    static func freshDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    /// A fresh `PersistenceStore` plus its suite name and resolved defaults.
    static func freshPersistence() -> (store: PersistenceStore, defaults: UserDefaults, suiteName: String) {
        let (defaults, suiteName) = freshDefaults()
        return (PersistenceStore(suiteName: suiteName), defaults, suiteName)
    }
}
