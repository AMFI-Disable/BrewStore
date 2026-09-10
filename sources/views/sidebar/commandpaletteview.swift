import AppKit
import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var discovery: BrewStoreDiscoveryCatalog
    @Binding var selection: BrewStoreSection?
    @Binding var isPresented: Bool

    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared
    @ObservedObject private var pinningManager = BrewStorePackagePinningManager.shared
    @ObservedObject private var preferences = BrewStorePreferences.shared

    @State private var query = ""
    @State private var selectedPackage: BrewStorePackage?
    @State private var selectedIndex = 0
    @State private var selectedCategory: PaletteCategory?
    @FocusState private var isSearchFocused: Bool

    enum PaletteCategory: String, CaseIterable {
        case actions = "Actions & Maintenance"
        case services = "Background Services"
        case packages = "Packages & Casks"
        case navigation = "Navigation"
    }

    struct PaletteItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let category: PaletteCategory
        let shortcut: String?
        let isInstalled: Bool?
        let kind: BrewPackageKind?
        let package: BrewStorePackage?
        let service: BrewStoreService?
        let execute: () -> Void
    }

    // MARK: - Pre-computed Items

    private var allItems: [PaletteItem] {
        var items: [PaletteItem] = []

        // 1. Actions & Maintenance
        items.append(contentsOf: [
            PaletteItem(
                id: "act-upgrade-all",
                title: "Upgrade All Outdated Packages",
                subtitle: "\(manager.packages.filter(\.isOutdated).count) packages have newer upstream versions available",
                icon: "arrow.up.circle.fill",
                category: .actions,
                shortcut: "⌘U",
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                manager.upgradeAllPackages()
                isPresented = false
            },
            PaletteItem(
                id: "act-update",
                title: "Fetch Homebrew Metadata (brew update)",
                subtitle: "Pull latest formulae, casks, and repository tap indices",
                icon: "arrow.triangle.2.circlepath",
                category: .actions,
                shortcut: "⌘R",
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                manager.updateHomebrew()
                discovery.load()
                isPresented = false
            },
            PaletteItem(
                id: "act-cleanup",
                title: "Clean Cache & Purge Downloads",
                subtitle: "Purge stale downloads and reclaim storage space (Mole / Brew Cleanup)",
                icon: "trash.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                manager.cleanup()
                isPresented = false
            },
            PaletteItem(
                id: "act-autoremove",
                title: "Remove Orphan Dependencies",
                subtitle: "Uninstall unused formula libraries no longer required by any tool",
                icon: "scissors",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                BrewStoreUninstallCoordinator.shared.requestAutoremove(manager: manager)
                isPresented = false
            },
            PaletteItem(
                id: "act-doctor",
                title: "Run Homebrew Doctor Diagnostics",
                subtitle: "Audit system installation for permission, path, and symlink issues",
                icon: "stethoscope",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                selection = .settings
                manager.runDoctor()
                isPresented = false
            },
            PaletteItem(
                id: "act-console",
                title: "Toggle Action Console Drawer",
                subtitle: "View live terminal stdout/stderr stream and command history",
                icon: "terminal.fill",
                category: .actions,
                shortcut: "⌥~",
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                withAnimation { preferences.showConsoleDrawer.toggle() }
                isPresented = false
            },
            PaletteItem(
                id: "act-snapshot",
                title: "Create Time Machine System Snapshot",
                subtitle: "Record active toolchain state for 1-click disaster rollback",
                icon: "camera.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                selection = .backups
                isPresented = false
            },
            PaletteItem(
                id: "act-sync-dotfiles",
                title: "Sync ~/Brewfile Dotfiles Bundle",
                subtitle: "Export installed packages cleanly to your home directory Brewfile",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                BrewStoreDotfilesAutoSyncManager.shared.syncNow(manager: manager)
                isPresented = false
            },
            PaletteItem(
                id: "act-reset",
                title: "Reset BrewStore Data & Settings…",
                subtitle: "Restore default preferences, purge catalog caches, or restore app defaults",
                icon: "arrow.counterclockwise.circle.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                selection = .settings
                BrewStoreResetManager.shared.showingResetSheet = true
                isPresented = false
            },
            PaletteItem(
                id: "act-dev-cache",
                title: "Clean Developer Caches (Xcode, Docker, npm, Cargo)",
                subtitle: "Safely purge bloated intermediate build outputs and caches to ~/.Trash",
                icon: "hammer.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                BrewStoreDeveloperCacheManager.shared.purgeSelected()
                isPresented = false
            },
            PaletteItem(
                id: "act-migrate-rosetta",
                title: "Migrate Rosetta 2 Apps to Native Apple Silicon",
                subtitle: "Reinstall Intel x86_64 binaries with native ARM64 versions to save battery",
                icon: "cpu",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                BrewStoreAppleSiliconMigrationManager.shared.migrateAllRosettaPackages(manager: manager)
                isPresented = false
            },
            PaletteItem(
                id: "act-blueprint-export",
                title: "Export Mac Setup Blueprint (~/Brewfile)",
                subtitle: "Create a complete snapshot of formulae, casks, MAS apps, and configurations",
                icon: "doc.badge.arrow.up",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                BrewStoreDotfilesAutoSyncManager.shared.syncNow(manager: manager)
                isPresented = false
            },
            PaletteItem(
                id: "act-dual-store-update",
                title: "Update All Software (Homebrew & Mac App Store)",
                subtitle: "One-click batch upgrade for both Homebrew and Mac App Store applications",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                BrewStoreUnifiedAppManager.shared.upgradeAllSoftware(homebrewManager: manager)
                isPresented = false
            },
            PaletteItem(
                id: "act-adopt-apps",
                title: "Scan & Adopt Unmanaged Applications",
                subtitle: "Discover unmanaged macOS apps and transition them into Homebrew management",
                icon: "app.badge.checkmark",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                selection = .adoption
                isPresented = false
            },
            PaletteItem(
                id: "act-manage-launchagents",
                title: "Manage Background Daemons & LaunchAgents",
                subtitle: "Inspect CPU, memory RSS, and active ports for Homebrew daemons and Login Items",
                icon: "gearshape.2.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                selection = .services
                isPresented = false
            }
        ])

        // 2. Services
        for service in manager.services {
            items.append(PaletteItem(
                id: "svc-\(service.name)",
                title: "\(service.isRunning ? "Stop" : "Start") Service: \(service.name)",
                subtitle: "Status: \(service.status.capitalized) · Background Daemon",
                icon: "server.rack",
                category: .services,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: service
            ) {
                manager.perform(service: service, action: service.isRunning ? .stop : .start)
                isPresented = false
            })
        }

        // 3. Navigation
        for section in BrewStoreSection.allCases {
            items.append(PaletteItem(
                id: "nav-\(section.rawValue)",
                title: "Go to \(section.rawValue)",
                subtitle: "Switch view to the \(section.rawValue) section",
                icon: section.icon,
                category: .navigation,
                shortcut: section == .settings ? "⌘," : nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil
            ) {
                selection = section
                isPresented = false
            })
        }

        // 4. Packages (if querying)
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matchedPackages = manager.packages.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                    $0.id.localizedCaseInsensitiveContains(query) ||
                    $0.description.localizedCaseInsensitiveContains(query)
            }.prefix(20)

            for pkg in matchedPackages {
                items.append(PaletteItem(
                    id: "pkg-\(pkg.kind.rawValue)-\(pkg.id)",
                    title: pkg.name,
                    subtitle: "\(pkg.id) · \(pkg.description.isEmpty ? (pkg.kind == .cask ? "macOS App" : "CLI Tool") : pkg.description)",
                    icon: pkg.kind == .cask ? "app.fill" : "terminal.fill",
                    category: .packages,
                    shortcut: nil,
                    isInstalled: pkg.isInstalled,
                    kind: pkg.kind,
                    package: pkg,
                    service: nil
                ) {
                    selectedPackage = pkg
                })
            }
        }

        return items
    }

    private var filteredItems: [PaletteItem] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseItems: [PaletteItem] = if let selectedCategory {
            allItems.filter { $0.category == selectedCategory }
        } else {
            cleanQuery.isEmpty ? allItems.filter { $0.category != .packages } : allItems
        }

        if cleanQuery.isEmpty {
            return baseItems
        }
        return baseItems.filter {
            $0.title.localizedCaseInsensitiveContains(cleanQuery) ||
                $0.subtitle.localizedCaseInsensitiveContains(cleanQuery) ||
                $0.id.localizedCaseInsensitiveContains(cleanQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Search Input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title2.bold())
                    .foregroundStyle(Color.accentColor)

                TextField("Type a command, package, service, or destination…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.medium))
                    .focused($isSearchFocused)
                    .onKeyPress(.downArrow) {
                        if !filteredItems.isEmpty {
                            selectedIndex = (selectedIndex + 1) % filteredItems.count
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if !filteredItems.isEmpty {
                            selectedIndex = (selectedIndex - 1 + filteredItems.count) % filteredItems.count
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        isPresented = false
                        return .handled
                    }
                    .onSubmit {
                        if filteredItems.indices.contains(selectedIndex) {
                            filteredItems[selectedIndex].execute()
                        }
                    }
                    .accessibilityLabel("Command Palette Search Field")
                    .accessibilityHint("Type to filter commands, use up and down arrow keys to navigate, enter to execute, escape to close")

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search query")
                }

                Button("ESC") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)
                .font(.caption2.bold())
                .accessibilityLabel("Close Command Palette")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))

            // Category Filter Pills
            HStack(spacing: 6) {
                categoryFilterPill(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                    selectedIndex = 0
                }

                ForEach(PaletteCategory.allCases, id: \.self) { cat in
                    categoryFilterPill(title: cat.rawValue, isSelected: selectedCategory == cat) {
                        selectedCategory = cat
                        selectedIndex = 0
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

            Divider()

            // Result List
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No matching commands or packages found for '\(query)'")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(
                        get: { selectedIndex },
                        set: { newIndex in
                            if let newIndex {
                                selectedIndex = newIndex
                            }
                        }
                    )) {
                        ForEach(Array(filteredItems.enumerated()), id: \.offset) { index, item in
                            Button {
                                item.execute()
                            } label: {
                                HStack(spacing: 12) {
                                    // Icon with tinted backing
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(iconBackgroundColor(for: item))
                                            .frame(width: 32, height: 32)

                                        Image(systemName: item.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(iconForegroundColor(for: item))
                                    }

                                    // Title and Subtitle
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.title)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }

                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    // Badges and Shortcuts
                                    if let isInstalled = item.isInstalled {
                                        Text(isInstalled ? "Installed" : "Available")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(isInstalled ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12), in: Capsule())
                                            .foregroundStyle(isInstalled ? .green : .secondary)
                                    }

                                    if let shortcut = item.shortcut {
                                        Text(shortcut)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(item.title), \(item.subtitle)")
                            .accessibilityHint("Return or click to execute")
                            .tag(index)
                            .id(index)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: selectedIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            Divider()

            // Raycast-Style Shortcut Helper Footer
            HStack(spacing: 16) {
                if filteredItems.indices.contains(selectedIndex) {
                    let activeItem = filteredItems[selectedIndex]
                    HStack(spacing: 6) {
                        Image(systemName: activeItem.icon)
                            .font(.caption2)
                            .foregroundStyle(iconForegroundColor(for: activeItem))
                        Text(activeItem.title)
                            .font(.caption2.bold())
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                } else {
                    Text("No item selected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 220, alignment: .leading)
                }

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "return")
                        .font(.caption2.bold())
                    Text("Execute")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.caption2.bold())
                    Text("Navigate")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 5) {
                    Image(systemName: "escape")
                        .font(.caption2.bold())
                    Text("Close")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        }
        .frame(width: 620, height: 460)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 24, y: 10)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
        .detailModalOverlay(item: $selectedPackage) { pkg in
            PackageDetailView(manager: manager, package: pkg, onDismiss: {
                selectedPackage = nil
            })
        }
    }

    private func iconBackgroundColor(for item: PaletteItem) -> Color {
        switch item.category {
        case .actions: Color.orange.opacity(0.15)
        case .services: Color.green.opacity(0.15)
        case .packages: (item.kind == .cask ? Color.blue : Color.purple).opacity(0.15)
        case .navigation: Color.accentColor.opacity(0.15)
        }
    }

    private func iconForegroundColor(for item: PaletteItem) -> Color {
        switch item.category {
        case .actions: Color.orange
        case .services: Color.green
        case .packages: item.kind == .cask ? Color.blue : Color.purple
        case .navigation: Color.accentColor
        }
    }

    private func categoryFilterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(title)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
