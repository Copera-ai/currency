import CurrencyKit
import SwiftUI

/// The menu bar popover: header, converter, tracked pairs and footer.
/// The popover itself provides the Liquid Glass background.
struct PopoverView: View {
    static let width: CGFloat = 360

    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader()
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            ConverterCard()
                .padding(.horizontal, 12)

            PairsSection()
                .padding(.top, 14)

            PopoverFooter()
        }
        .frame(width: Self.width)
        .background {
            if store.settings.reduceTransparency {
                Rectangle().fill(.background).padding(-20)
            }
        }
        .tint(store.settings.accent.color)
        .onExitCommand { model.actions.closePopover() }
        .background {
            // Keyboard shortcuts for the popover window.
            Group {
                Button("Refresh") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Settings") { model.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Header

struct PopoverHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Exchange Rates")
                    .font(.system(size: 15, weight: .semibold))
                statusLine
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, options: reduceMotion ? .nonRepeating : .repeat(.continuous), isActive: store.isRefreshing)
                        .frame(width: 18, height: 18)
                }
                .help("Refresh (⌘R)")
                .accessibilityLabel("Refresh rates")

                Button {
                    model.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 18, height: 18)
                }
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(nil)
        }
    }

    private var statusLine: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(spacing: 5) {
                if let status = DegradedStatus(store.loadState) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(store.isRefreshing && store.lastUpdated == nil ? "Loading rates…" : store.updatedText(relativeTo: context.date))
                    .contentTransition(.opacity)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
}

/// A short description of a degraded ``LoadState``.
struct DegradedStatus {
    let title: String
    let detail: String
    let symbol: String
    let color: Color

    init?(_ state: LoadState) {
        switch state {
        case .offline:
            title = "You're offline"
            detail = "Showing the last rates we fetched."
            symbol = "wifi.slash"
            color = .orange
        case .stale:
            title = "Rates may be out of date"
            detail = "The last refresh didn't complete."
            symbol = "clock.badge.exclamationmark"
            color = .yellow
        case .error(let error):
            title = "Couldn't load rates"
            detail = error.localizedDescription
            symbol = "exclamationmark.triangle"
            color = .red
        case .idle, .loading, .loaded:
            return nil
        }
    }
}

// MARK: - Footer

struct PopoverFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(CurrencyStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let status = DegradedStatus(store.loadState) {
                banner(status)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let version = model.updater.availableUpdateVersion {
                updateRow(version)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            Divider()
                .padding(.horizontal, 12)
            HStack {
                Button {
                    model.openSettings(.currencies)
                } label: {
                    Label("Manage Currencies…", systemImage: "slider.horizontal.3")
                }
                Spacer()
                Button {
                    model.quit()
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .help("Quit Copera Currency (⌘Q)")
                .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .motion(reduceMotion, value: store.loadState.isDegraded)
    }

    /// Gentle reminder for an update found by a scheduled check (see ``Updater``).
    private func updateRow(_ version: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 20)
            Text("Version \(version) is available")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 6)
            Button("Update…") { model.checkForUpdates() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(10)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func banner(_ status: DegradedStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(status.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(status.title).font(.system(size: 12, weight: .semibold))
                Text(status.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 6)
            Button("Retry") { model.refresh() }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(store.isRefreshing)
        }
        .padding(10)
        .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(status.color.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}
