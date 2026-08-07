import SwiftUI

struct BrewStoreRootView: View {
    @ObservedObject var manager: HomebrewManager
    @State private var selection: BrewStoreSection? = .apps

    var body: some View {
        NavigationSplitView {
            List(BrewStoreSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section as BrewStoreSection?)
            }
            .navigationTitle("BrewStore")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Circle()
                        .fill(manager.isAvailable ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(manager.isAvailable ? "Homebrew ready" : "Homebrew required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        } detail: {
            if !manager.isAvailable && selection != .settings {
                HomebrewSetupView(manager: manager)
            } else {
                switch selection ?? .apps {
                case .apps:
                    PackageListView(manager: manager, kind: .cask, title: "Apps")
                case .formulae:
                    PackageListView(manager: manager, kind: .formula, title: "Formulae")
                case .updates:
                    PackageListView(manager: manager, kind: nil, title: "Updates", updatesOnly: true)
                case .services:
                    ServicesView(manager: manager)
                case .taps:
                    TapsView(manager: manager)
                case .settings:
                    SettingsView(manager: manager)
                }
            }
        }
        .task {
            if manager.isAvailable { manager.refresh() }
        }
    }
}
