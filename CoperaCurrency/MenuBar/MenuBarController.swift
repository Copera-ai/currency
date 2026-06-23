import AppKit
import Observation

/// Owns the dynamic set of ``StatusItemController``s — one per tracked pair —
/// keyed by pair id and ordered to match ``RatesStore/trackedSorted``.
///
/// ## Diffing strategy
/// `NSStatusItem` has no public ordering API; items appear in creation order
/// (newest closest to the clock). So the only way to enforce order is to rebuild
/// the items whenever the *membership or order* changes — never on rate ticks.
///
/// Rate/change ticks are handled entirely by SwiftUI: each ``StatusItemLabelView``
/// observes the store directly and re-renders itself. This controller therefore
/// only watches the *ordered id list* (`trackedSorted.map(\.id)`); when that list
/// differs from the last-known one, it tears down and rebuilds all items in the
/// new order.
///
/// ## Observing `@Observable` outside SwiftUI
/// Since this is a plain AppKit object (not a SwiftUI view), it uses
/// `withObservationTracking` to react to store changes, re-arming the tracking
/// after each fire (the closure only fires once per registration).
@MainActor
final class MenuBarController {
    private let store: RatesStore
    private let settings: AppSettings
    private let popoverController: PopoverController
    private let onOpenSettings: () -> Void

    /// Live status-item controllers, keyed by pair id. Strong refs: required or
    /// the underlying `NSStatusItem`s are released and disappear.
    private var items: [Int: StatusItemController] = [:]
    /// The ordered id list the current items reflect; the diff signal.
    private var currentOrderedIDs: [Int] = []

    init(
        store: RatesStore,
        settings: AppSettings,
        popoverController: PopoverController,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.popoverController = popoverController
        self.onOpenSettings = onOpenSettings
    }

    /// Build the initial items and begin observing membership/order changes.
    func start() {
        rebuildIfNeeded()
        observeTrackedChanges()
    }

    // MARK: - Observation

    /// Register a one-shot observation of the tracked-pair ordering, re-arming
    /// after it fires. Accessing `store.trackedSorted` inside the `apply` block
    /// registers it (and its dependencies `pairs`) as a dependency.
    private func observeTrackedChanges() {
        withObservationTracking {
            // Touch the membership/order signal to register the dependency.
            _ = store.trackedSorted
        } onChange: { [weak self] in
            // Fired off the main actor's run loop; hop back to apply + re-arm.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildIfNeeded()
                self.observeTrackedChanges()
            }
        }
    }

    // MARK: - Diff + rebuild

    /// Rebuild all status items iff the ordered id list actually changed.
    private func rebuildIfNeeded() {
        let tracked = store.trackedSorted
        let newOrderedIDs = tracked.map(\.id)
        guard newOrderedIDs != currentOrderedIDs else { return }

        // No in-place reordering API; tear down and rebuild in the target order.
        // Closing the popover avoids it pointing at a button we're removing.
        popoverController.close()
        for controller in items.values {
            controller.remove()
        }
        items.removeAll(keepingCapacity: true)

        for pair in tracked {
            items[pair.id] = StatusItemController(
                pair: pair,
                store: store,
                settings: settings,
                popoverController: popoverController,
                onOpenSettings: onOpenSettings
            )
        }

        currentOrderedIDs = newOrderedIDs
    }
}
