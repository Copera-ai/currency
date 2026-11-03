#if DEBUG
import AppKit
import CurrencyKit

/// Launch arguments that drive the UI for screenshots and manual QA (Debug builds only):
///
///     open "Copera Currency.app" --args -UITestOpenPopover YES -UITestAppearance dark
///
/// - `-UITestAppearance light|dark|auto`: overrides Light/Dark for the popover and
///   Settings without touching the saved preference.
/// - `-UITestOpenPopover YES`: shows the popover.
/// - `-UITestExpandPair BTC/USD`: expands that pair's chart (implies the popover).
/// - `-UITestOpenPicker from|to`: opens the converter's currency picker (implies the popover).
/// - `-UITestOpenSettings general|currencies|appearance|about`: opens Settings on a tab.
/// - `-UITestAddPair YES`: opens Settings › Currencies with the Add Pair sheet.
/// - `-UITestBackdrop light|dark`: puts a full-screen, wallpaper-like gradient behind the
///   app's windows so Liquid Glass samples a clean backdrop instead of whatever is on
///   screen, and leaves the converter's amount field unfocused (no selection highlight).
@MainActor
enum DebugLaunchHooks {
    private static var backdrop: NSWindow?

    static func run(model: AppModel) {
        let defaults = UserDefaults.standard
        let backdropStyle = defaults.string(forKey: "UITestBackdrop")
        if let backdropStyle { showBackdrop(dark: backdropStyle == "dark") }
        if let raw = defaults.string(forKey: "UITestAppearance"), let appearance = AppearancePreference(rawValue: raw) {
            model.appearanceOverride = appearance
        }
        let expand = defaults.string(forKey: "UITestExpandPair")
        let picker = defaults.string(forKey: "UITestOpenPicker")
        let openPopover = defaults.bool(forKey: "UITestOpenPopover") || expand != nil || picker != nil
        let settingsTab = defaults.string(forKey: "UITestOpenSettings").flatMap(SettingsTab.init(rawValue:))
        let addPair = defaults.bool(forKey: "UITestAddPair")

        Task { @MainActor in
            // Let the status items and the settings bridge settle, and the first rates arrive.
            try? await Task.sleep(for: .seconds(1.5))
            if openPopover {
                model.actions.showPopover()
                if backdropStyle != nil { clearKeyboardFocus() }
                if let expand { model.expandedPairID = expand }
                if let picker {
                    try? await Task.sleep(for: .milliseconds(400))
                    model.pickerSide = picker == "to" ? .to : .from
                }
            }
            if addPair {
                model.addPairFromAnywhere()
            } else if let settingsTab {
                model.openSettings(settingsTab)
            }
            if backdropStyle != nil {
                NSApp.activate()
                if openPopover, picker == nil {
                    try? await Task.sleep(for: .milliseconds(300))
                    clearKeyboardFocus()
                }
            }
        }
    }

    /// Resigns the first responder in the popover so the amount isn't shown selected.
    private static func clearKeyboardFocus() {
        for window in NSApp.windows where window.isVisible && window !== backdrop {
            if String(describing: type(of: window)).contains("Popover") {
                window.makeFirstResponder(nil)
            }
        }
    }

    private static func showBackdrop(dark: Bool) {
        guard let screen = NSScreen.main else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = BackdropView(dark: dark)
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)
        backdrop = window
    }
}

/// A soft gradient with two colored glows, like a desktop wallpaper.
private final class BackdropView: NSView {
    private let base = CAGradientLayer()
    private let glows: [(layer: CAGradientLayer, center: CGPoint, radius: CGFloat)]

    init(dark: Bool) {
        // Base gradient (top-left → bottom-right), then a glow top-right and one bottom-left.
        let baseHex = dark ? ["#0A1F24", "#0E1430"] : ["#F7EBDD", "#DCE7F7"]
        let glowHex = dark ? ["#0F6B4C", "#3A2466"] : ["#BDEBD8", "#F9D3C3"]
        base.colors = baseHex.map { NSColor(hex: $0).cgColor }
        base.startPoint = CGPoint(x: 0, y: 1)
        base.endPoint = CGPoint(x: 1, y: 0)
        glows = [(glowHex[0], CGPoint(x: 0.85, y: 0.9), 0.75), (glowHex[1], CGPoint(x: 0.1, y: 0.15), 0.7)].map { hex, center, radius in
            let layer = CAGradientLayer()
            layer.type = .radial
            let color = NSColor(hex: hex)
            layer.colors = [color.withAlphaComponent(dark ? 0.75 : 0.9).cgColor, color.withAlphaComponent(0).cgColor]
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            return (layer, center, radius)
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(base)
        for glow in glows { layer?.addSublayer(glow.layer) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.frame = bounds
        for glow in glows {
            let side = max(bounds.width, bounds.height) * glow.radius * 2
            glow.layer.frame = CGRect(
                x: bounds.width * glow.center.x - side / 2,
                y: bounds.height * glow.center.y - side / 2,
                width: side,
                height: side
            )
        }
        CATransaction.commit()
    }
}
#endif
