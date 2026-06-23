import AppKit
import SwiftUI

/// Owns the single shared transient ``NSPopover`` used by every status item.
///
/// One popover is reused across all status items: `toggle(relativeTo:)` shows it
/// anchored to a button, hides it if it's already shown for that same button, or
/// moves it when a different button is clicked. The anchored button is
/// highlighted while the popover is open and un-highlighted on close (via the
/// popover delegate).
///
/// Phase 2 hosts a STUB content view (``PopoverStubView``) that lists the tracked
/// pairs with live rates — enough to confirm wiring. Phase 3 swaps in the real
/// `PopoverView` (see `setContent(_:)`).
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    /// Fixed popover width per the design (intrinsic height).
    static let width: CGFloat = 368

    private let popover: NSPopover
    private let store: RatesStore
    private let settings: AppSettings

    /// The button the popover is currently anchored to (for highlight bookkeeping).
    private weak var anchorButton: NSStatusBarButton?

    init(store: RatesStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = makeStubContentController()
    }

    /// Phase-2 stub content. Phase 3 replaces this with the real popover UI; the
    /// controller only needs the hosting swap, not a behavioral change here.
    private func makeStubContentController() -> NSViewController {
        let controller = NSHostingController(
            rootView: PopoverStubView(store: store, settings: settings)
        )
        controller.view.frame = NSRect(x: 0, y: 0, width: Self.width, height: 320)
        return controller
    }

    /// Show or hide the popover relative to the given status-item button.
    ///
    /// - Already shown for this button → close.
    /// - Shown for a different button → move (close, re-anchor, reopen).
    /// - Hidden → show anchored to this button.
    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            if anchorButton === button {
                close()
                return
            }
            close()
        }
        show(relativeTo: button)
    }

    private func show(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        button.highlight(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Close the popover if shown (e.g. before opening the Settings window).
    func close() {
        if popover.isShown {
            popover.performClose(nil)
        }
        anchorButton?.highlight(false)
        anchorButton = nil
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        // Transient dismissal (click-outside, Esc) routes here too; drop the
        // active button highlight.
        anchorButton?.highlight(false)
        anchorButton = nil
    }
}

// MARK: - Stub content

/// Phase-2 placeholder popover content: title + a live list of tracked pairs.
///
/// Reads the `@Observable` store so the rates/changes refresh live. Replaced by
/// the real `PopoverView` in Phase 3.
struct PopoverStubView: View {
    let store: RatesStore
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copera Currency")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.trackedSorted) { pair in
                    PopoverStubRow(pair: pair, store: store)
                }
            }

            Divider()

            Text(store.relativeUpdatedLabel())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: PopoverController.width, alignment: .leading)
    }
}

/// A single tracked-pair row in the stub popover.
private struct PopoverStubRow: View {
    let pair: CurrencyPair
    let store: RatesStore

    var body: some View {
        let change = store.change(pair)
        let trend = Trend(change: change)

        HStack {
            Text("\(pair.base)/\(pair.quote)")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(store.fmt(store.rate(pair)))
                .font(.system(size: 13, design: .monospaced))
                .monospacedDigit()
            if let arrow = trend.arrow {
                Text(arrow)
                    .font(.system(size: 10))
                    .foregroundStyle(trend == .up ? Color.green : Color.red)
            }
        }
    }
}
