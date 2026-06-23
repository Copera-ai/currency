import SwiftUI

// MARK: - SettingsTab

/// The four sections of the Settings window. Drives the sidebar selection and
/// the deep-link target carried in from the popover.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case currencies
    case appearance
    case about

    var id: String { rawValue }

    /// Sidebar / topbar label.
    var title: String {
        switch self {
        case .general: return "General"
        case .currencies: return "Currencies"
        case .appearance: return "Appearance"
        case .about: return "About"
        }
    }

    /// SF Symbol shown in the leading nav badge.
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .currencies: return "dollarsign"
        case .appearance: return "circle.lefthalf.filled"
        case .about: return "info"
        }
    }

    /// The badge's brand color (matches the design's nav badge tokens).
    var navColor: Color {
        switch self {
        case .general: return Theme.navGeneral
        case .currencies: return Theme.navCurrencies
        case .appearance: return Theme.navAppearance
        case .about: return Theme.navAbout
        }
    }
}

// MARK: - RefreshInterval display name

extension RefreshInterval {
    /// Human-readable name for the Settings picker (e.g. "5 minutes").
    /// Defined here (not in the data layer) to keep the store/tests untouched.
    var displayName: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .threeHours: return "3 hours"
        }
    }
}

// MARK: - SettingsRoot

/// The Settings window content: a custom 208pt sidebar + 48pt topbar + detail
/// area. Built by hand (not `NavigationSplitView`) for pixel control over the
/// design. The selected tab can be set on appear for deep-linking from the
/// popover ("Manage" → Currencies).
struct SettingsRoot: View {
    let store: RatesStore
    @Bindable var settings: AppSettings

    /// Initial / externally-set tab. `SettingsWindowController.show(tab:)` updates
    /// this so an already-open window jumps to the requested section.
    let initialTab: SettingsTab

    @Environment(\.theme) private var theme
    @State private var selection: SettingsTab = .general
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(width: 680, height: 496)
        .background(theme.settingsContent)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            selection = initialTab
            withAnimation(.easeOut(duration: 0.2)) { appeared = true }
        }
        // Reflect an external deep-link target if the window is reused.
        .onChange(of: initialTab) { _, newValue in
            withAnimation(.easeOut(duration: 0.18)) { selection = newValue }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 2) {
            // Leave room below the window's native title bar / traffic lights.
            Spacer().frame(height: 12)
            ForEach(SettingsTab.allCases) { tab in
                sidebarRow(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 208)
        .frame(maxHeight: .infinity)
        .background(theme.settingsSidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.sep).frame(width: hairline)
        }
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        let selected = selection == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = tab }
        } label: {
            HStack(spacing: 10) {
                NavBadge(systemName: tab.symbol, color: tab.navColor, selected: selected)
                Text(tab.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.white : theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            // Topbar with the active tab's title.
            HStack {
                Text(selection.title)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(theme.text)
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 48)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.sep).frame(height: hairline)
            }

            // Scrollable section body.
            ScrollView {
                content
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                    .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.settingsContent)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            SettingsGeneralTab(store: store, settings: settings) {
                withAnimation(.easeOut(duration: 0.18)) { selection = .currencies }
            }
        case .currencies:
            SettingsCurrenciesTab(store: store, settings: settings)
        case .appearance:
            SettingsAppearanceTab(settings: settings)
        case .about:
            SettingsAboutTab()
        }
    }
}
