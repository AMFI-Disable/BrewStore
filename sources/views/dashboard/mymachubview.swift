import AppKit
import SwiftUI

enum MyMacSubMode: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case updates = "Updates"
    case wishlist = "Wishlist"
    case adoption = "Adoption"
    case topology = "Dependencies"

    var id: String {
        rawValue
    }

    var section: BrewStoreSection {
        switch self {
        case .installed: .installed
        case .updates: .updates
        case .wishlist: .wishlist
        case .adoption: .adoption
        case .topology: .topology
        }
    }

    init?(section: BrewStoreSection) {
        switch section {
        case .installed: self = .installed
        case .updates: self = .updates
        case .wishlist: self = .wishlist
        case .adoption: self = .adoption
        case .topology: self = .topology
        default: return nil
        }
    }
}

struct MyMacHubView: View {
    @ObservedObject var manager: HomebrewManager
    @Binding var selection: BrewStoreSection?

    @State private var subMode: MyMacSubMode = .installed
    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared
    @ObservedObject private var adoptionManager = BrewStoreAppAdoptionManager.shared
    @ObservedObject private var masManager = BrewStoreMASManager.shared
    @ObservedObject private var unifiedManager = BrewStoreUnifiedAppManager.shared

    private var installedCount: Int {
        manager.packages.filter(\.isInstalled).count
    }

    private var outdatedCount: Int {
        manager.packages.filter(\.isOutdated).count + masManager.outdatedApps.count
    }

    private var wishlistCount: Int {
        wishlistManager.wishlistIDs.count
    }

    private var adoptableCount: Int {
        adoptionManager.adoptableApps.count + adoptionManager.reviewRequiredApps.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // ZONE 1: Hub Header & Anchor Controls
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "shippingbox.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            Text("My Mac")
                                .font(.title2.bold())
                        }
                        Text("Installed software, pending updates, wishlist, and app adoption.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Zone 1 Primary Contextual Action
                    HStack(spacing: Spacing.sm) {
                        if subMode == .updates, outdatedCount > 0 {
                            Button {
                                unifiedManager.upgradeAllSoftware(homebrewManager: manager)
                            } label: {
                                Label("Update All (\(outdatedCount))", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(manager.isOperating || masManager.isOperating)
                        }

                        Button(action: manager.refresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(manager.isLoading || manager.isOperating)
                    }
                }

                // Zone 1: Segmented Switcher
                HStack {
                    Picker("My Mac Navigation", selection: $subMode) {
                        Text("Installed (\(installedCount))").tag(MyMacSubMode.installed)
                        Text(outdatedCount > 0 ? "Updates (\(outdatedCount))" : "Updates").tag(MyMacSubMode.updates)
                        Text("Wishlist (\(wishlistCount))").tag(MyMacSubMode.wishlist)
                        Text("Adoption (\(adoptableCount))").tag(MyMacSubMode.adoption)
                        Text("Dependencies").tag(MyMacSubMode.topology)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: subMode) { _, newMode in
                        if selection != newMode.section {
                            selection = newMode.section
                        }
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)

            Divider()

            // ZONE 3: Primary Content Canvas
            Group {
                switch subMode {
                case .installed:
                    PackageListView(manager: manager, kind: nil, title: "Installed", installedOnly: true, showHeader: false)
                case .updates:
                    PackageListView(manager: manager, kind: nil, title: "Updates", updatesOnly: true, showHeader: false)
                case .wishlist:
                    WishlistView(manager: manager, showHeader: false)
                case .adoption:
                    AppAdoptionView(manager: manager, showHeader: false)
                case .topology:
                    DependencyTopologyView(manager: manager, showHeader: false)
                }
            }
            .id(subMode)
            .animation(nil, value: subMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            syncFromSelection()
            unifiedManager.rebuildInventory(homebrewManager: manager)
        }
        .onChange(of: selection) { _, _ in
            syncFromSelection()
        }
        .onChange(of: manager.packages) { _, _ in
            unifiedManager.rebuildInventory(homebrewManager: manager)
        }
        .onChange(of: masManager.installedApps) { _, _ in
            unifiedManager.rebuildInventory(homebrewManager: manager)
        }
    }

    private func syncFromSelection() {
        if let current = selection, let mapped = MyMacSubMode(section: current) {
            if subMode != mapped {
                subMode = mapped
            }
        }
    }
}
