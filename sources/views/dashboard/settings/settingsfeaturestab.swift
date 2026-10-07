import AppKit
import SwiftUI

struct SettingsFeaturesTab: View {
    @ObservedObject private var preferences = BrewStorePreferences.shared
    @StateObject private var watchdog = BrewStoreServiceWatchdog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Configure storefront modules, package details, and background services.")
                .font(.body)
                .foregroundStyle(.secondary)

            storefrontModulesSection
            packageDetailFeaturesSection
            backupsAndSyncSection
            watchdogSection
        }
    }

    private var storefrontModulesSection: some View {
        SettingsCardSection(title: "Storefront Modules", icon: "sparkles") {
            Toggle("Editorial Stories", isOn: $preferences.enableEditorialStories)
            Text("Show curated articles and package collections in the sidebar.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Developer Toolkits", isOn: $preferences.enableDeveloperStacks)
            Text("Show curated package toolkits in the sidebar.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var packageDetailFeaturesSection: some View {
        SettingsCardSection(title: "Package Details", icon: "cube.transparent") {
            Toggle("Dependency Graphs", isOn: $preferences.enableVisualDependencyGraph)
            Text("Show interactive dependency trees on package detail pages.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("App Cleaner", isOn: $preferences.enableAppCleaner)
            Text("Scan for leftover files and caches when uninstalling applications.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Default Uninstallation Method")
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

    private var backupsAndSyncSection: some View {
        SettingsCardSection(title: "Backups & Sync", icon: "shield.lefthalf.filled") {
            Toggle("Snapshot before uninstalling", isOn: $preferences.enableAutoSnapshotBeforeMutations)
            Text("Automatically saves a Brewfile snapshot before packages are removed.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Sync Brewfile to GitHub Gist", isOn: $preferences.enableAutoGistCloudSync)
            Text("Automatically syncs your package list to a private GitHub Gist.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var watchdogSection: some View {
        SettingsCardSection(title: "Service Watchdog", icon: "shield.checkered") {
            Toggle("Monitor background services", isOn: $watchdog.isWatchdogEnabled)
            Text("Checks running services and notifies you if a daemon stops unexpectedly.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if watchdog.isWatchdogEnabled {
                Divider()
                Toggle("Automatically restart stopped services", isOn: $watchdog.autoRestartOnCrash)
                Text("Attempts to relaunch services that exit with an error code.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
