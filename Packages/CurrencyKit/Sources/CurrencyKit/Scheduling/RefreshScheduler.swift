import Foundation

/// Why a refresh was requested.
public enum RefreshTrigger: String, Hashable, Sendable, CaseIterable {
    case launch
    case timer
    case wake
    case networkRestored
    case manual

    /// Whether this trigger should bypass TTLs and backoff.
    public var forcesRefresh: Bool {
        switch self {
        case .manual, .wake, .networkRestored: true
        case .launch, .timer: false
        }
    }

    /// Whether this trigger skips the debounce window.
    var firesImmediately: Bool {
        self == .manual || self == .launch
    }
}

/// Merges timer, wake, network-restored and manual triggers into debounced refreshes.
///
/// - Triggers arriving within ``debounce`` of each other fire one refresh carrying all of them
///   (manual and launch triggers fire immediately).
/// - The periodic timer counts from the last refresh of any kind, so a manual refresh
///   postpones the next automatic one.
/// - ``setInterval(_:)`` takes effect immediately: the pending sleep is cancelled and the
///   next fire is rescheduled (or fires right away if already overdue).
@MainActor
public final class RefreshScheduler {
    public typealias Action = @MainActor (Set<RefreshTrigger>) async -> Void

    public private(set) var interval: Duration
    public let debounce: Duration

    private let action: Action
    private let clock = ContinuousClock()
    private var lastFire: ContinuousClock.Instant?
    private var timerTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var pending: Set<RefreshTrigger> = []
    private var isRunning = false
    private var isFiring = false

    public init(interval: Duration, debounce: Duration = .milliseconds(750), action: @escaping Action) {
        self.interval = interval
        self.debounce = debounce
        self.action = action
    }

    /// Starts the periodic timer and fires a `.launch` refresh.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        trigger(.launch)
        scheduleTimer()
    }

    /// Stops everything. Pending triggers are dropped.
    public func stop() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        pending.removeAll()
    }

    /// Changes the periodic interval, cancelling the current sleep.
    public func setInterval(_ newValue: Duration) {
        guard newValue != interval else { return }
        interval = newValue
        Log.scheduler.info("Interval changed to \(newValue)")
        if isRunning { scheduleTimer() }
    }

    /// Requests a refresh. Coalesced with other triggers inside the debounce window.
    public func trigger(_ trigger: RefreshTrigger) {
        guard isRunning else { return }
        pending.insert(trigger)
        if trigger.firesImmediately {
            debounceTask?.cancel()
            debounceTask = nil
            Task { await self.fire() }
            return
        }
        guard debounceTask == nil else { return }
        debounceTask = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self.debounceTask = nil
            await self.fire()
        }
    }

    private func fire() async {
        guard isRunning, !pending.isEmpty else { return }
        if isFiring {
            // Re-check once the running refresh finishes.
            return
        }
        let triggers = pending
        pending.removeAll()
        isFiring = true
        lastFire = clock.now
        Log.scheduler.debug("Firing refresh for \(triggers.map(\.rawValue).sorted().joined(separator: ","), privacy: .public)")
        await action(triggers)
        isFiring = false
        if !pending.isEmpty, debounceTask == nil {
            await fire()
        }
        if !triggers.contains(.timer) { scheduleTimer() }
    }

    private func scheduleTimer() {
        timerTask?.cancel()
        let deadline = (lastFire ?? clock.now) + interval
        timerTask = Task { [clock] in
            do {
                try await Task.sleep(until: deadline, clock: clock)
            } catch {
                return
            }
            guard !Task.isCancelled, self.isRunning else { return }
            self.pending.insert(.timer)
            await self.fire()
            if !Task.isCancelled { self.scheduleTimer() }
        }
    }
}
