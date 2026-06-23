import SwiftUI

/// Appearance settings: light/dark/auto, accent color, menu-bar format, and
/// reduce-transparency. Changing the appearance also syncs the AppKit chrome
/// (status-item labels, popover) so they follow the SwiftUI tree live.
struct SettingsAppearanceTab: View {
    @Bindable var settings: AppSettings

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            SettingRow(
                title: "Appearance",
                subtitle: "Match the system or pick a mode"
            ) {
                SegmentedControl(
                    options: AppAppearance.allCases,
                    selection: appearanceBinding,
                    title: { $0.displayName }
                )
                .frame(width: 200)
            }

            SettingRow(
                title: "Accent color",
                subtitle: "Highlights and selected states"
            ) {
                HStack(spacing: 10) {
                    ForEach(AccentChoice.allCases, id: \.self) { choice in
                        AccentSwatch(
                            choice: choice,
                            isSelected: settings.accent == choice
                        ) {
                            settings.accent = choice
                        }
                    }
                }
            }

            SettingRow(
                title: "Menu bar format",
                subtitle: "How the rate reads up top"
            ) {
                SegmentedControl(
                    options: LabelFormat.allCases,
                    selection: $settings.menuBarFormat,
                    title: { $0.displayName }
                )
                .frame(width: 200)
            }

            SettingRow(
                title: "Reduce transparency",
                subtitle: "Use solid panels instead of blur",
                showSeparator: false
            ) {
                AppToggle(isOn: $settings.reduceTransparency)
            }
        }
    }

    /// Wraps `settings.appearance` so AppKit chrome re-syncs on every change.
    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { settings.appearance },
            set: { newValue in
                settings.appearance = newValue
                AppearanceSync.apply(newValue)
            }
        )
    }
}
