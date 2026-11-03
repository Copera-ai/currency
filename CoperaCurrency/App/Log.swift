import os

/// App-target loggers (CurrencyKit has its own).
enum Log {
    private static let subsystem = "ai.copera.currency"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let windows = Logger(subsystem: subsystem, category: "windows")
}
