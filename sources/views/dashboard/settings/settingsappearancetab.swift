import AppKit
import SwiftUI

struct SettingsAppearanceTab: View {
    @ObservedObject private var themeManager = BrewStoreThemeVibrancyManager.shared
    @ObservedObject private var preferences = BrewStorePreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            accentThemesSection
            windowVibrancySection
            cleanInterfaceSection
        }
    }

    private var accentThemesSection: some View {
        SettingsCardSection(title: "Custom Accent Themes", icon: "paintbrush.fill") {
            Text("Select an accent color palette that matches your desktop aesthetic.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 10) {
                ForEach(AppAccentTheme.allCases) { theme in
                    Button {
                        themeManager.currentTheme = theme
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(theme.color).frame(width: 14, height: 14)
                            Text(theme.rawValue).font(.subheadline)
                            Spacer()
                            if themeManager.currentTheme == theme {
                                Image(systemName: "checkmark").font(.caption.bold())
                                    .foregroundStyle(theme.color)
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(themeManager.currentTheme == theme ? theme.color : Color.secondary.opacity(0.12), lineWidth: themeManager.currentTheme == theme ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var windowVibrancySection: some View {
        SettingsCardSection(title: "Window Glassmorphism & Vibrancy", icon: "macwindow.on.rectangle") {
            Picker("Vibrancy Material", selection: $themeManager.vibrancyLevel) {
                ForEach(WindowVibrancyLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Text("Adjust macOS window translucency and background vibrancy blending.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var cleanInterfaceSection: some View {
        SettingsCardSection(title: "Clean Interface & Decluttering", icon: "eye.slash") {
            Toggle("Hide 100% Completed Bundles", isOn: $preferences.hideCompletedBundles)
            Text("Automatically hide developer bundles and toolkits when all contained formulae and casks are installed.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Hide Installed Wishlist Items", isOn: $preferences.hideInstalledWishlist)
            Text("Keep your starred wishlist focused on pending tools by hiding packages already installed.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Hide In-Sync Snapshots (0 Differences)", isOn: $preferences.hideIdenticalSnapshots)
            Text("Only display snapshots that have differences from your current system state.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
