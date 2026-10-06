import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case features = "Features"
    case network = "Network & Mirrors"
    case snapshots = "Snapshots & Brewfile"
    case doctor = "Doctor & Health"
    case storage = "Storage & Privacy"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .features: "sparkles"
        case .network: "network"
        case .snapshots: "clock.arrow.circlepath"
        case .doctor: "stethoscope"
        case .storage: "externaldrive.fill"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var updateMonitor: BrewStoreUpdateMonitor
    var discovery: BrewStoreDiscoveryCatalog = BrewStoreDiscoveryCatalog()

    @ObservedObject private var resetManager = BrewStoreResetManager.shared
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            tabPicker
            Divider()
            tabContent
        }
        .sheet(isPresented: $resetManager.showingResetSheet) {
            ResetViewSheet(manager: manager, discovery: discovery)
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Settings").font(.largeTitle.bold())
                Text("Manage updates, appearance, package sources, backups, and privacy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.clearPersonalSettings]) {
                    resetManager.showingResetSheet = true
                }
            } label: {
                Label("Reset App…", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xs)
    }

    private var tabPicker: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.lg)
        }
        .padding(.bottom, Spacing.sm)
    }

    private var tabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                switch selectedTab {
                case .general:
                    SettingsGeneralTab(manager: manager, updateMonitor: updateMonitor)
                case .appearance:
                    SettingsAppearanceTab()
                case .features:
                    SettingsFeaturesTab()
                case .network:
                    SettingsNetworkTab(manager: manager)
                case .snapshots:
                    SettingsSnapshotsTab(manager: manager)
                case .doctor:
                    SettingsDoctorTab(manager: manager)
                case .storage:
                    SettingsStorageTab(manager: manager, discovery: discovery)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .id(selectedTab)
        .animation(nil, value: selectedTab)
    }
}
