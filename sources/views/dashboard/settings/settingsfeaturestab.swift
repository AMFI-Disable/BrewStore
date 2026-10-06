import AppKit
import SwiftUI

struct SettingsFeaturesTab: View {
    @ObservedObject private var preferences = BrewStorePreferences.shared
    @StateObject private var watchdog = BrewStoreServiceWatchdog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Customize BrewStore's innovation modules and discovery experiences.")
                .font(.body)
                .foregroundStyle(.secondary)

            storefrontModulesSection
            packageDetailInnovationsSection
            safetyAndCloudSyncSection
            watchdogSection
        }
    }

    private var storefrontModulesSection: some View {
        SettingsCardSection(title: "Storefront & Discovery Modules", icon: "sparkles") {
            Toggle("Editorial Stories & Curated Deep-Dives", isOn: $preferences.enableEditorialStories)
            Text("Long-form articles with 1-click package install pills in the sidebar and storefront.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Developer Toolkits & Stacks", isOn: $preferences.enableDeveloperStacks)
            Text("Curated 1-click bundle suites for Web, Mobile, Data, and System engineering.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var packageDetailInnovationsSection: some View {
        SettingsCardSection(title: "Package Detail Innovations", icon: "cube.transparent") {
            Toggle("Visual Dependency Graphs", isOn: $preferences.enableVisualDependencyGraph)
            Text("Render interactive visual relationship trees showing direct and required packages.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("App Cleaner (Residual File Scanner)", isOn: $preferences.enableAppCleaner)
            Text("Scan Application Support, Caches, and preference leftovers when uninstalling Casks.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Default App Replacement & Uninstallation Strategy")
                    .font(.body)
                Picker("", selection: $preferences.defaultUninstallMode) {
                    ForEach(BrewStoreAppUninstallMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Text(preferences.defaultUninstallMode.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var safetyAndCloudSyncSection: some View {
        SettingsCardSection(title: "Safety & Cloud Sync Policies", icon: "shield.lefthalf.filled") {
            Toggle("Auto-Snapshot before destructive package uninstallations", isOn: $preferences.enableAutoSnapshotBeforeMutations)
            Text("Automatically records Time-Machine Brewfile snapshots before removing packages.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Auto-Sync Brewfile to GitHub Private Gist on changes", isOn: $preferences.enableAutoGistCloudSync)
            Text("Automatically push cloud backups when packages or taps are altered.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var watchdogSection: some View {
        SettingsCardSection(title: "Background Service Crash Watchdog", icon: "shield.checkered") {
            Toggle("Monitor active background services for crashes", isOn: $watchdog.isWatchdogEnabled)
            Text("Periodically inspects daemons (Redis, Postgres, Nginx) and alerts if a service crashes.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if watchdog.isWatchdogEnabled {
                Divider()
                Toggle("Auto-Restart crashed services automatically", isOn: $watchdog.autoRestartOnCrash)
                Text("Immediately attempts to relaunch any daemon that exits with an error status.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
