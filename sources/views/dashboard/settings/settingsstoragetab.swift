import AppKit
import SwiftUI

struct SettingsStorageTab: View {
    @ObservedObject var manager: HomebrewManager
    var discovery: BrewStoreDiscoveryCatalog
    @ObservedObject private var resetManager = BrewStoreResetManager.shared

    @State private var showingResetPreferencesConfirm = false
    @State private var showingClearCacheConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DiskStorageView(manager: manager)
            diskSpaceAllocationSection
            privacyPolicySection
            operationHistorySection
            resetDataManagementSection
        }
        .sheet(isPresented: $resetManager.showingResetSheet) {
            ResetViewSheet(manager: manager, discovery: discovery)
        }
    }

    private var diskSpaceAllocationSection: some View {
        SettingsCardSection(title: "Disk Space Allocation", icon: "internaldrive") {
            LabeledContent("Cellar (Formulae)", value: manager.storageUsage.formattedCellar)
            LabeledContent("Caskroom (Apps)", value: manager.storageUsage.formattedCaskroom)
            LabeledContent("Download Cache", value: manager.storageUsage.formattedCache)
            Divider()
            LabeledContent("Total Disk Usage", value: manager.storageUsage.formattedTotal)

            Button("Recalculate Storage", action: manager.calculateStorageUsage)
                .controlSize(.small)
        }
    }

    private var privacyPolicySection: some View {
        SettingsCardSection(title: "Privacy & Analytics Policy", icon: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                    Text("BrewStore Application: 100% Local & Private").font(.subheadline.bold())
                }
                Text("BrewStore does not collect, track, or transmit your searches, installed inventory, or machine identifiers to any remote analytics server.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Homebrew Anonymous Analytics").font(.subheadline.bold())
                        Text("Controls Homebrew's upstream command-line analytics (brew analytics off/on). When enabled, Homebrew sends anonymous usage stats to the Homebrew project.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let isEnabled = manager.isAnalyticsEnabled {
                        Toggle("", isOn: Binding(
                            get: { isEnabled },
                            set: { manager.setAnalytics(enabled: $0) }
                        ))
                        .labelsHidden()
                        .disabled(manager.isOperating)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var operationHistorySection: some View {
        if !manager.operationHistory.isEmpty {
            SettingsCardSection(title: "Operation History", icon: "list.bullet.rectangle") {
                HStack {
                    Text("\(manager.operationHistory.count) operations recorded").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History", role: .destructive, action: manager.clearOperationHistory)
                        .controlSize(.small)
                }

                ForEach(manager.operationHistory.prefix(8)) { operation in
                    HStack(spacing: 8) {
                        Image(systemName: operation.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(operation.succeeded ? .green : .red)
                        Text(operation.title).font(.caption.bold())
                        Spacer()
                        Text(operation.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var resetDataManagementSection: some View {
        SettingsCardSection(title: "Reset & Data Management", icon: "arrow.counterclockwise") {
            Text("Restore specific configurations to default, clear cached Homebrew indexes, or restore application defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                Button("Reset Preferences") {
                    showingResetPreferencesConfirm = true
                }
                .controlSize(.small)
                .confirmationDialog("Reset Preferences?", isPresented: $showingResetPreferencesConfirm, titleVisibility: .visible) {
                    Button("Reset Preferences", role: .destructive) {
                        resetManager.resetPreferences()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will revert all application settings and toggles to their default values.")
                }

                Button("Clear Catalog Cache") {
                    showingClearCacheConfirm = true
                }
                .controlSize(.small)
                .confirmationDialog("Clear Catalog Cache?", isPresented: $showingClearCacheConfirm, titleVisibility: .visible) {
                    Button("Clear Cache", role: .destructive) {
                        resetManager.resetDiscoveryCache(discovery: discovery)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will delete local cached formula and cask indexes and re-fetch them from the official Homebrew catalog.")
                }

                Button("Reset Wishlist") {
                    BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.unstarEverything]) {
                        resetManager.resetWishlist()
                    }
                }
                .controlSize(.small)

                Button("Reset Version Pins") {
                    BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.unpinEverything]) {
                        resetManager.resetPinnedPackages(manager: manager)
                    }
                }
                .controlSize(.small)

                Button("Clear Logs & History") {
                    BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.cleanupEverything]) {
                        resetManager.resetHistoryAndLogs(manager: manager)
                    }
                }
                .controlSize(.small)

                Button("Reset Appearance") {
                    BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.clearPersonalSettings]) {
                        resetManager.resetThemeAndAppearance()
                    }
                }
                .controlSize(.small)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore App Defaults").font(.subheadline.bold())
                    Text("Reverts interface preferences and local caches back to initial defaults.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset Everything…", role: .destructive) {
                    resetManager.showingResetSheet = true
                }
                .controlSize(.regular)
            }
        }
    }
}
