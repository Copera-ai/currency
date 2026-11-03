import AppKit
import Foundation
import Network

/// Calls ``onWake`` when the Mac wakes from sleep.
@MainActor
public final class WakeObserver {
    public var onWake: (@MainActor () -> Void)?
    private var token: (any NSObjectProtocol)?

    public init() {}

    public func start() {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onWake?() }
        }
    }

    public func stop() {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = nil
    }
}

/// Edge detector for connectivity. The first observation only records the state;
/// afterwards an unsatisfied → satisfied transition counts as "restored".
public struct ReachabilityTracker: Sendable {
    public private(set) var isSatisfied: Bool?

    public init() {}

    /// Records `satisfied` and returns whether connectivity was just restored.
    public mutating func update(satisfied: Bool) -> Bool {
        let previous = isSatisfied
        isSatisfied = satisfied
        return previous == false && satisfied
    }
}

/// Watches the network path. Calls ``onRestored`` when connectivity comes back and
/// exposes ``isOnline`` for offline detection.
@MainActor
public final class NetworkMonitor {
    public var onRestored: (@MainActor () -> Void)?
    public var onChange: (@MainActor (Bool) -> Void)?
    private var tracker = ReachabilityTracker()
    private var monitor: NWPathMonitor?

    public init() {}

    /// `nil` until the first path update arrives.
    public var isOnline: Bool? { tracker.isSatisfied }

    public func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        // Deliver on the main queue so updates stay ordered and main-actor isolated.
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            MainActor.assumeIsolated { self?.handle(satisfied: satisfied) }
        }
        self.monitor = monitor
        monitor.start(queue: .main)
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
        tracker = ReachabilityTracker()
    }

    /// Exposed for tests; normally driven by `NWPathMonitor`.
    func handle(satisfied: Bool) {
        // Record the new state first so anything the callbacks trigger sees it.
        let restored = tracker.update(satisfied: satisfied)
        onChange?(satisfied)
        if restored {
            Log.scheduler.info("Network restored")
            onRestored?()
        }
    }
}
