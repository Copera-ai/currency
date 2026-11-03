import os

/// Loggers for the `ai.copera.currency` subsystem.
enum Log {
    static let subsystem = "ai.copera.currency"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let history = Logger(subsystem: subsystem, category: "history")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let scheduler = Logger(subsystem: subsystem, category: "scheduler")
    static let catalog = Logger(subsystem: subsystem, category: "catalog")
    static let store = Logger(subsystem: subsystem, category: "store")
}
