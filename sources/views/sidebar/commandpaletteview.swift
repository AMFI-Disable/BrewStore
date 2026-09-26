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
    @State private var toastMessage: String?
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
        let commandSnippet: String?
        let impactBadge: String?
        let execute: () -> Void

        init(
            id: String,
            title: String,
            subtitle: String,
            icon: String,
            category: PaletteCategory,
            shortcut: String?,
            isInstalled: Bool?,
            kind: BrewPackageKind?,
            package: BrewStorePackage?,
            service: BrewStoreService?,
            commandSnippet: String? = nil,
            impactBadge: String? = nil,
            execute: @escaping () -> Void
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.icon = icon
            self.category = category
            self.shortcut = shortcut
            self.isInstalled = isInstalled
            self.kind = kind
            self.package = package
            self.service = service
            self.commandSnippet = commandSnippet
            self.impactBadge = impactBadge
            self.execute = execute
        }

        init(
            id: String,
            title: String,
            subtitle: String,
            icon: String,
            category: PaletteCategory,
            shortcut: String?,
            isInstalled: Bool?,
            kind: BrewPackageKind?,
            package: BrewStorePackage?,
            service: BrewStoreService?,
            execute: @escaping () -> Void
        ) {
            self.init(
                id: id,
                title: title,
                subtitle: subtitle,
                icon: icon,
                category: category,
                shortcut: shortcut,
                isInstalled: isInstalled,
                kind: kind,
                package: package,
                service: service,
                commandSnippet: nil,
                impactBadge: nil,
                execute: execute
            )
        }
    }

    // MARK: - Pre-computed Items

    private var allItems: [PaletteItem] {
        var items: [PaletteItem] = []

        // 1. Actions & Maintenance
        items.append(contentsOf: actionItems)

        // 2. Services
        items.append(contentsOf: serviceItems)

        // 3. Navigation
        items.append(contentsOf: navigationItems)

        // 4. Packages
        items.append(contentsOf: packageItems)

        return items
    }

    private var actionItems: [PaletteItem] {
        [
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
                service: nil,
                commandSnippet: "brew upgrade",
                impactBadge: "Batch Upgrade"
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
                service: nil,
                commandSnippet: "brew update",
                impactBadge: "Index Refresh"
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
                service: nil,
                commandSnippet: "brew cleanup --prune=all",
                impactBadge: "Disk Space"
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
                service: nil,
                commandSnippet: "brew autoremove",
                impactBadge: "Dependency Prune"
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
                service: nil,
                commandSnippet: "brew doctor",
                impactBadge: "Health Diagnostic"
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
                service: nil,
                commandSnippet: "brew log",
                impactBadge: "Live Stream"
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
                service: nil,
                commandSnippet: "brew bundle dump",
                impactBadge: "State Snapshot"
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
                service: nil,
                commandSnippet: "brew bundle --file=~/Brewfile",
                impactBadge: "Dotfiles Backup"
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
                service: nil,
                commandSnippet: "defaults delete com.brewstore",
                impactBadge: "Preferences Reset"
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
                service: nil,
                commandSnippet: "rm -rf ~/Library/Caches/com.apple.dt.Xcode",
                impactBadge: "Developer Cleanup"
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
                service: nil,
                commandSnippet: "arch -arm64 brew reinstall",
                impactBadge: "ARM64 Migration"
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
                service: nil,
                commandSnippet: "brew bundle dump --file=~/Brewfile",
                impactBadge: "Export Blueprint"
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
                service: nil,
                commandSnippet: "brew upgrade && mas upgrade",
                impactBadge: "Universal Update"
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
                service: nil,
                commandSnippet: "brew list --cask",
                impactBadge: "Adoption Scan"
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
                service: nil,
                commandSnippet: "brew services list",
                impactBadge: "Process Monitor"
            ) {
                selection = .services
                isPresented = false
            },
            PaletteItem(
                id: "act-simulate-blast-radius",
                title: "Simulate Package Blast Radius…",
                subtitle: "Inspect reverse dependencies and daemon impacts before uninstallation",
                icon: "waveform.path.ecg",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil,
                commandSnippet: "brew uses --installed",
                impactBadge: "Pre-Flight Check"
            ) {
                selection = .topology
                isPresented = false
            },
            PaletteItem(
                id: "act-scavenge-baggage",
                title: "Scavenge Build Baggage & Orphaning",
                subtitle: "Inspect and prune dormant build-only compilers and header dependencies",
                icon: "archivebox.circle.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil,
                commandSnippet: "brew autoremove --dry-run",
                impactBadge: "Build Baggage"
            ) {
                selection = .topology
                isPresented = false
            },
            PaletteItem(
                id: "act-export-dependency-graph",
                title: "Export Dependency Graph (Graphviz / Mermaid)",
                subtitle: "Generate topological graph visualizations and lockfile diagrams",
                icon: "point.3.connected.trianglepath.dotted",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil,
                commandSnippet: "brew deps --tree --installed",
                impactBadge: "Topology Export"
            ) {
                selection = .topology
                isPresented = false
            },
            PaletteItem(
                id: "act-self-healing-doctor",
                title: "Autonomous Doctor ICU & Remediation",
                subtitle: "Automated root-cause analysis and 1-click self-healing for Homebrew issues",
                icon: "cross.case.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil,
                commandSnippet: "brew doctor && brew cleanup",
                impactBadge: "Self Healing"
            ) {
                selection = .settings
                manager.runDoctor()
                isPresented = false
            },
            PaletteItem(
                id: "act-time-machine-timeline",
                title: "Cellar Time Machine & Snapshot Replay",
                subtitle: "Browse chronological system states and replay safe rollbacks",
                icon: "clock.arrow.circlepath",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil,
                commandSnippet: "brew bundle --rollback",
                impactBadge: "Zero-Regret Replay"
            ) {
                selection = .backups
                isPresented = false
            },
            PaletteItem(
                id: "act-packaging-studio",
                title: "Developer Formula & Cask Packaging Studio",
                subtitle: "Create, SHA256-hash, audit, and publish custom Homebrew packages",
                icon: "shippingbox.circle.fill",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil,
                commandSnippet: "brew create",
                impactBadge: "Packaging Studio"
            ) {
                selection = .creator
                isPresented = false
            },
            PaletteItem(
                id: "act-fleet-sync-profiles",
                title: "Multi-Machine Fleet Sync & Profile Drift",
                subtitle: "Reconcile configuration drift against curated developer role profiles",
                icon: "macbook.and.iphone",
                category: .actions,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil,
                commandSnippet: "brew bundle check",
                impactBadge: "Fleet Drift"
            ) {
                selection = .backups
                isPresented = false
            }
        ]
    }

    private var serviceItems: [PaletteItem] {
        manager.services.map { service in
            PaletteItem(
                id: "svc-\(service.name)",
                title: "\(service.isRunning ? "Stop" : "Start") Service: \(service.name)",
                subtitle: "Status: \(service.status.capitalized) · Background Daemon",
                icon: "server.rack",
                category: .services,
                shortcut: nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: service,
                commandSnippet: "brew services \(service.isRunning ? "stop" : "start") \(service.name)",
                impactBadge: service.isRunning ? "Running Daemon" : "Stopped Daemon"
            ) {
                manager.perform(service: service, action: service.isRunning ? .stop : .start)
                isPresented = false
            }
        }
    }

    private var navigationItems: [PaletteItem] {
        BrewStoreSection.allCases.map { section in
            PaletteItem(
                id: "nav-\(section.rawValue)",
                title: "Go to \(section.rawValue)",
                subtitle: "Switch view to the \(section.rawValue) section",
                icon: section.icon,
                category: .navigation,
                shortcut: section == .settings ? "⌘," : nil,
                isInstalled: nil,
                kind: nil,
                package: nil,
                service: nil,
                commandSnippet: "open brewstore://\(section.rawValue.lowercased())",
                impactBadge: "Navigation"
            ) {
                selection = section
                isPresented = false
            }
        }
    }

    private var packageItems: [PaletteItem] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [BrewStorePackage]

        if cleanQuery.isEmpty {
            var defaults: [BrewStorePackage] = []
            let outdated = manager.packages.filter(\.isOutdated)
            defaults.append(contentsOf: outdated.prefix(8))

            let pinnedIDs = pinningManager.pinnedPackageIDs
            let pinned = manager.packages.filter { pinnedIDs.contains($0.id) && !defaults.contains($0) }
            defaults.append(contentsOf: pinned.prefix(4))

            if defaults.count < 12 {
                let installed = manager.packages.filter { $0.isInstalled && !defaults.contains($0) }
                defaults.append(contentsOf: installed.prefix(12 - defaults.count))
            }
            candidates = defaults
        } else {
            candidates = Array(manager.packages.filter {
                $0.name.localizedCaseInsensitiveContains(cleanQuery) ||
                    $0.id.localizedCaseInsensitiveContains(cleanQuery) ||
                    $0.description.localizedCaseInsensitiveContains(cleanQuery)
            }.prefix(25))
        }

        return candidates.map { pkg in
            let actionSnippet: String = if pkg.isInstalled {
                pkg.isOutdated ? "brew upgrade \(pkg.id)" : "brew uninstall \(pkg.id)"
            } else {
                pkg.kind == .cask ? "brew install --cask \(pkg.id)" : "brew install \(pkg.id)"
            }

            let badge: String = if pkg.isOutdated {
                "Update Available"
            } else if pkg.isInstalled {
                "Installed"
            } else {
                "Available"
            }

            return PaletteItem(
                id: "pkg-\(pkg.kind.rawValue)-\(pkg.id)",
                title: pkg.name,
                subtitle: "\(pkg.id) · \(pkg.description.isEmpty ? (pkg.kind == .cask ? "macOS App" : "CLI Tool") : pkg.description)",
                icon: pkg.kind == .cask ? "app.fill" : "terminal.fill",
                category: .packages,
                shortcut: nil,
                isInstalled: pkg.isInstalled,
                kind: pkg.kind,
                package: pkg,
                service: nil,
                commandSnippet: actionSnippet,
                impactBadge: badge
            ) {
                selectedPackage = pkg
            }
        }
    }

    private var filteredItems: [PaletteItem] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseItems: [PaletteItem] = if let selectedCategory {
            allItems.filter { $0.category == selectedCategory }
        } else {
            allItems
        }

        if cleanQuery.isEmpty {
            return baseItems
        }
        return BrewStoreFuzzySearchEngine.filterAndRank(
            items: baseItems,
            query: cleanQuery,
            minimumScore: 1
        ) { item in
            [item.title, item.subtitle, item.id, item.commandSnippet ?? ""]
        }
    }

    private var currentSelectedItem: PaletteItem? {
        guard filteredItems.indices.contains(selectedIndex) else { return nil }
        return filteredItems[selectedIndex]
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerSearchBar
            categoryFilterBar
            Divider()

            HStack(spacing: 0) {
                // Left Column: Results List (460pt)
                leftResultsColumn
                    .frame(width: 460)

                // Vertical Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 1)

                // Right Column: Live Inspector (319pt)
                rightInspectorColumn
                    .frame(width: 319)
            }
            .frame(maxHeight: .infinity)

            Divider()
            shortcutFooter
        }
        .frame(width: 780, height: 520)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if let toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(toastMessage)
                        .font(.caption.bold())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .padding(.bottom, 50)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .shadow(color: Color.black.opacity(0.24), radius: 30, y: 12)
        .background {
            categoryKeyboardShortcuts
        }
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
        .onChange(of: filteredItems.count) {
            if selectedIndex >= filteredItems.count {
                selectedIndex = max(0, filteredItems.count - 1)
            }
        }
        .detailModalOverlay(item: $selectedPackage) { pkg in
            PackageDetailView(manager: manager, package: pkg, onDismiss: {
                selectedPackage = nil
            })
        }
    }

    // MARK: - Header & Filters

    private var headerSearchBar: some View {
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
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
    }

    private var categoryFilterBar: some View {
        HStack(spacing: 6) {
            categoryFilterPill(title: "All", shortcut: "⌘1", isSelected: selectedCategory == nil) {
                selectedCategory = nil
                selectedIndex = 0
            }

            categoryFilterPill(title: "Actions", shortcut: "⌘2", isSelected: selectedCategory == .actions) {
                selectedCategory = .actions
                selectedIndex = 0
            }

            categoryFilterPill(title: "Services", shortcut: "⌘3", isSelected: selectedCategory == .services) {
                selectedCategory = .services
                selectedIndex = 0
            }

            categoryFilterPill(title: "Packages", shortcut: "⌘4", isSelected: selectedCategory == .packages) {
                selectedCategory = .packages
                selectedIndex = 0
            }

            categoryFilterPill(title: "Navigation", shortcut: "⌘5", isSelected: selectedCategory == .navigation) {
                selectedCategory = .navigation
                selectedIndex = 0
            }

            Spacer()

            Text("\(filteredItems.count) items")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private func categoryFilterPill(title: String, shortcut: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text(shortcut)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .opacity(isSelected ? 0.9 : 0.5)
            }
            .font(.caption2.bold())
            .padding(.horizontal, 8)
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

    private var categoryKeyboardShortcuts: some View {
        Group {
            Button("") {
                selectedCategory = nil
                selectedIndex = 0
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("") {
                selectedCategory = .actions
                selectedIndex = 0
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("") {
                selectedCategory = .services
                selectedIndex = 0
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("") {
                selectedCategory = .packages
                selectedIndex = 0
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("") {
                selectedCategory = .navigation
                selectedIndex = 0
            }
            .keyboardShortcut("5", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: - Left Column: Results List

    @ViewBuilder
    private var leftResultsColumn: some View {
        if filteredItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("No matching commands or packages found for '\(query)'")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !query.isEmpty {
                    Button("Clear Query") {
                        query = ""
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
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
                        resultRow(item: item, isSelected: selectedIndex == index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIndex == index {
                                    item.execute()
                                } else {
                                    selectedIndex = index
                                }
                            }
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
    }

    private func resultRow(item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(iconBackgroundColor(for: item))
                    .frame(width: 28, height: 28)

                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconForegroundColor(for: item))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let isInstalled = item.isInstalled {
                Text(isInstalled ? "Installed" : "Available")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isInstalled ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(isInstalled ? .green : .secondary)
            }

            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.subtitle)")
        .accessibilityHint("Return or click to execute")
    }

    // MARK: - Right Column: Live Inspector

    private var rightInspectorColumn: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                if let item = currentSelectedItem {
                    if let pkg = item.package {
                        packageInspector(pkg: pkg, item: item)
                    } else if let svc = item.service {
                        serviceInspector(svc: svc, item: item)
                    } else if item.category == .actions {
                        actionInspector(item: item)
                    } else if item.category == .navigation {
                        navigationInspector(item: item)
                    }
                } else {
                    emptyInspectorPlaceholder
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private func packageInspector(pkg: BrewStorePackage, item: PaletteItem) -> some View {
        let isWishlisted = wishlistManager.isWishlisted(id: pkg.id)
        let isPinned = pinningManager.isPinned(packageID: pkg.id)

        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(pkg.kind == .cask ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: pkg.kind == .cask ? "app.fill" : "terminal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(pkg.kind == .cask ? Color.blue : Color.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(pkg.name)
                        .font(.headline.bold())
                        .lineLimit(1)
                    Text(pkg.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Badges
            HStack(spacing: 6) {
                Text(pkg.kind == .cask ? "Cask App" : "Formula")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                if pkg.isInstalled {
                    Text(pkg.isOutdated ? "Outdated" : "Installed")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(pkg.isOutdated ? Color.orange.opacity(0.16) : Color.green.opacity(0.16), in: Capsule())
                        .foregroundStyle(pkg.isOutdated ? .orange : .green)
                } else {
                    Text("Available")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                if isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("About")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(pkg.description.isEmpty ? "No description provided." : pkg.description)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Specifications
            VStack(alignment: .leading, spacing: 6) {
                Text("Specifications")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                specRow(label: "Version", value: pkg.version.isEmpty ? "Unknown" : pkg.version)
                specRow(label: "Tap", value: pkg.tap ?? "homebrew/core")
                if !pkg.dependencies.isEmpty {
                    specRow(label: "Dependencies", value: "\(pkg.dependencies.count) linked")
                }
                if !pkg.homepage.isEmpty {
                    specRow(label: "Homepage", value: pkg.homepage, isLink: true)
                }
            }

            Divider()

            // Terminal Command Snippet Box
            if let snippet = item.commandSnippet {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Terminal Command")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyToClipboard(snippet, label: "'\(snippet)'")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Copy CLI command to clipboard")
                    }

                    Text(snippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Quick Actions
            VStack(spacing: 6) {
                Button {
                    selectedPackage = pkg
                } label: {
                    Label("Open Package Details", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                HStack(spacing: 8) {
                    if pkg.isInstalled {
                        if pkg.isOutdated {
                            Button {
                                manager.perform(package: pkg, action: .upgrade)
                                isPresented = false
                            } label: {
                                Label("Upgrade", systemImage: "arrow.up.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.orange)
                        }

                        Button(role: .destructive) {
                            BrewStoreUninstallCoordinator.shared.requestUninstall(package: pkg, manager: manager)
                            isPresented = false
                        } label: {
                            Label("Uninstall", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button {
                            manager.perform(package: pkg, action: .install)
                            isPresented = false
                        } label: {
                            Label("Install", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.green)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        pinningManager.togglePin(package: pkg, manager: manager)
                    } label: {
                        Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        wishlistManager.toggleWishlist(id: pkg.id)
                    } label: {
                        Label(isWishlisted ? "Starred" : "Star", systemImage: isWishlisted ? "star.fill" : "star")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(isWishlisted ? Color.yellow : Color.primary)
                }
            }
        }
    }

    private func serviceInspector(svc: BrewStoreService, item: PaletteItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "server.rack")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(svc.name)
                        .font(.headline.bold())
                        .lineLimit(1)
                    Text("Background Daemon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(svc.isRunning ? Color.green : (svc.isError ? Color.red : Color.secondary))
                    .frame(width: 8, height: 8)

                Text(svc.isRunning ? "Active Daemon" : (svc.isError ? "Error" : "Stopped"))
                    .font(.caption.bold())
                    .foregroundStyle(svc.isRunning ? .green : (svc.isError ? .red : .secondary))

                Spacer()

                if let user = svc.user, !user.isEmpty {
                    Text("User: \(user)")
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            Divider()

            // Details
            VStack(alignment: .leading, spacing: 6) {
                Text("Daemon Information")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                specRow(label: "Status", value: svc.status.capitalized)
                if let file = svc.file {
                    specRow(label: "Plist Path", value: file)
                }
            }

            Divider()

            // Command Snippet
            if let snippet = item.commandSnippet {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Terminal Command")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyToClipboard(snippet, label: "'\(snippet)'")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Copy CLI command to clipboard")
                    }

                    Text(snippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Quick Actions
            VStack(spacing: 8) {
                Button {
                    item.execute()
                } label: {
                    Label(svc.isRunning ? "Stop Service" : "Start Service", systemImage: svc.isRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(svc.isRunning ? .red : .green)

                Button {
                    manager.perform(service: svc, action: .restart)
                    isPresented = false
                } label: {
                    Label("Restart Service", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    selection = .services
                    isPresented = false
                } label: {
                    Label("View In Services Manager", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func actionInspector(item: PaletteItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: item.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline.bold())
                        .lineLimit(2)
                    if let badge = item.impactBadge {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Action Description")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Command Snippet
            if let snippet = item.commandSnippet {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Equivalent CLI Command")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyToClipboard(snippet, label: "'\(snippet)'")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Copy CLI command to clipboard")
                    }

                    Text(snippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Divider()

            // Run Button
            Button {
                item.execute()
            } label: {
                Label("Execute Action", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
        }
    }

    private func navigationInspector(item: PaletteItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: item.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline.bold())
                        .lineLimit(1)
                    Text("Sidebar Navigation Hub")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Destination")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let shortcut = item.shortcut {
                HStack {
                    Text("Keyboard Shortcut")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(shortcut)
                        .font(.caption.bold().monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            Divider()

            // Go Button
            Button {
                item.execute()
            } label: {
                Label("Switch to Section", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func specRow(label: String, value: String, isLink: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            if isLink, let url = URL(string: value) {
                Link(destination: url) {
                    Text(value)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(value)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var emptyInspectorPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "command")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("Select an item to view inspector")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var shortcutFooter: some View {
        HStack(spacing: 14) {
            if let activeItem = currentSelectedItem {
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

            if let activeItem = currentSelectedItem, let snippet = activeItem.commandSnippet {
                Button {
                    copyToClipboard(snippet, label: "'\(snippet)'")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy CLI")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                Text("Execute")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 10, weight: .bold))
                Text("Navigate")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "escape")
                    .font(.system(size: 10, weight: .bold))
                Text("Close")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String, label: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            toastMessage = "Copied \(label)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                if toastMessage == "Copied \(label)" {
                    toastMessage = nil
                }
            }
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
}
