import AppKit
import SwiftUI

struct BrewStoreRootView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var discovery: BrewStoreDiscoveryCatalog
    @ObservedObject var updateMonitor: BrewStoreUpdateMonitor
    @Binding var selection: BrewStoreSection?
    @Binding var showingCommandPalette: Bool
    @Binding var showingHelpSheet: Bool

    @ObservedObject var preferences = BrewStorePreferences.shared
    @ObservedObject private var themeManager = BrewStoreThemeVibrancyManager.shared
    @ObservedObject private var uninstallCoordinator = BrewStoreUninstallCoordinator.shared
    @ObservedObject private var actionReviewCoordinator = BrewStoreActionReviewCoordinator.shared
    @StateObject private var githubAccount = GitHubAccountManager()
    @ObservedObject private var gitService = GitServiceManager.shared
    @State private var showingGitHubSheet = false
    @State private var showingAISheet = false
    @State private var showingShellConfigSheet = false
    @State private var showingHealthSheet = false
    @State private var showingBrewfileImportSheet = false
    @State private var deepLinkedPackage: BrewStorePackage?

    @AppStorage("Sidebar.Expanded.Hub.Storefront") private var isStorefrontExpanded = true
    @AppStorage("Sidebar.Expanded.Hub.MyMac") private var isMyMacExpanded = true
    @AppStorage("Sidebar.Expanded.Hub.Environment") private var isEnvironmentExpanded = true
    @AppStorage("Sidebar.Expanded.Hub.Health") private var isHealthExpanded = true

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    hubCollapsibleSection(for: .storefront, isExpanded: $isStorefrontExpanded)
                    hubCollapsibleSection(for: .myMac, isExpanded: $isMyMacExpanded)
                    hubCollapsibleSection(for: .environment, isExpanded: $isEnvironmentExpanded)
                    hubCollapsibleSection(for: .health, isExpanded: $isHealthExpanded)

                    Section {
                        subSidebarRow(for: .settings)
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("System")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selection) { _, newSelection in
                    guard let newSelection else { return }
                    switch newSelection.hub {
                    case .storefront:
                        if !isStorefrontExpanded {
                            isStorefrontExpanded = true
                        }
                    case .myMac:
                        if !isMyMacExpanded {
                            isMyMacExpanded = true
                        }
                    case .environment:
                        if !isEnvironmentExpanded {
                            isEnvironmentExpanded = true
                        }
                    case .health:
                        if !isHealthExpanded {
                            isHealthExpanded = true
                        }
                    case .settings:
                        break
                    }
                }

                sidebarFooter
            }
            .frame(width: BrewStoreSplitViewManager.fixedSidebarWidth)
            .navigationSplitViewColumnWidth(min: BrewStoreSplitViewManager.fixedSidebarWidth, ideal: BrewStoreSplitViewManager.fixedSidebarWidth, max: BrewStoreSplitViewManager.fixedSidebarWidth)
            .background(BrewStoreSplitViewAccessor())
            .navigationTitle("BrewStore")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BrewStoreStatusHUDView(
                        manager: manager,
                        onOpenHealth: { showingHealthSheet = true },
                        onOpenServices: { selection = .services }
                    )
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    BrewStoreGlobalSearchBar(
                        manager: manager,
                        discovery: discovery,
                        selection: $selection,
                        onOpenPackage: { pkg in
                            deepLinkedPackage = pkg
                        },
                        onOpenAISearch: { _ in
                            showingAISheet = true
                        }
                    )
                    .accessibilityIdentifier("Toolbar.GlobalSearchBar")

                    Menu {
                        Button {
                            dismissSecondarySheets()
                            showingHealthSheet = true
                        } label: {
                            Label("Health Score & Optimizer", systemImage: "heart.text.square")
                        }
                        .accessibilityIdentifier("Toolbar.HealthScore")

                        Button {
                            dismissSecondarySheets()
                            showingAISheet = true
                        } label: {
                            Label("AI Package Assistant", systemImage: "wand.and.stars")
                        }
                        .accessibilityIdentifier("Toolbar.AIAssistant")

                        Button {
                            dismissSecondarySheets()
                            showingBrewfileImportSheet = true
                        } label: {
                            Label("Import Brewfile…", systemImage: "doc.badge.plus")
                        }
                        .accessibilityIdentifier("Toolbar.ImportBrewfile")

                        Button {
                            dismissSecondarySheets()
                            showingShellConfigSheet = true
                        } label: {
                            Label("Shell Environment Assistant…", systemImage: "terminal")
                        }
                        .accessibilityIdentifier("Toolbar.ShellSetup")
                        Divider()

                        Button {
                            showingHelpSheet = true
                        } label: {
                            Label("BrewStore Help Manual", systemImage: "questionmark.circle")
                        }
                        .keyboardShortcut("?", modifiers: .command)
                        .accessibilityIdentifier("Toolbar.Help")
                    } label: {
                        Label("Tools & Diagnostics", systemImage: "wrench.and.screwdriver")
                    }
                    .help("Tools, Diagnostics & Utilities")
                    .accessibilityIdentifier("Toolbar.ToolsMenu")

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            preferences.showConsoleDrawer.toggle()
                        }
                    } label: {
                        Label("Console", systemImage: preferences.showConsoleDrawer ? "terminal.fill" : "terminal")
                    }
                    .help("Toggle Action Console (⌥~)")
                    .keyboardShortcut("~", modifiers: .option)
                    .accessibilityIdentifier("Toolbar.Console")

                    Button {
                        showingCommandPalette = true
                    } label: {
                        Label("Quick Open", systemImage: "command")
                    }
                    .help("Quick Open (⌘K)")
                    .accessibilityIdentifier("Toolbar.QuickOpen")
                }
            }
        } detail: {
            VStack(spacing: 0) {
                BrewStoreRefreshRecoveryBanner(
                    manager: manager,
                    discovery: discovery,
                    onRetry: retryRefresh,
                    onClearCacheAndRetry: clearCacheAndRetry
                )

                NavigationStack {
                    Group {
                        if !manager.isAvailable, selection != .settings, selection != .discover {
                            HomebrewSetupView(manager: manager)
                        } else {
                            switch selection ?? .discover {
                            case .discover:
                                DiscoveryView(manager: manager, catalog: discovery, initialMode: .spotlight) { mode in
                                    syncSidebarSelection(for: mode)
                                }
                            case .allPackages:
                                DiscoveryView(manager: manager, catalog: discovery, initialMode: .allCatalog) { mode in
                                    syncSidebarSelection(for: mode)
                                }
                            case .showdown:
                                CommunityShowdownView(manager: manager, accountManager: githubAccount)
                            case .allApps:
                                DiscoveryView(manager: manager, catalog: discovery, initialMode: .allApps) { mode in
                                    syncSidebarSelection(for: mode)
                                }
                            case .allFormulae:
                                DiscoveryView(manager: manager, catalog: discovery, initialMode: .allFormulae) { mode in
                                    syncSidebarSelection(for: mode)
                                }
                            case .stories:
                                StoriesFeedView(manager: manager)
                            case .toolkits:
                                StacksView(manager: manager)
                            case .categories:
                                CategoriesGridView(manager: manager, catalog: discovery) { _ in
                                    selection = .discover
                                }
                            case .installed, .adoption, .topology, .wishlist, .updates:
                                MyMacHubView(manager: manager, selection: $selection)
                            case .workspaces:
                                WorkspacesView(manager: manager)
                            case .services, .taps, .creator:
                                EnvironmentHubView(manager: manager, selection: $selection, accountManager: githubAccount)
                            case .backups:
                                HealthHubView(manager: manager, selection: $selection)
                            case .settings:
                                SettingsView(manager: manager, updateMonitor: updateMonitor, discovery: discovery)
                            }
                        }
                    }
                    .navigationDestination(for: BrewStorePackage.self) { package in
                        PackageDetailView(manager: manager, package: package)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

                if preferences.showConsoleDrawer {
                    ActionConsoleDrawer(manager: manager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: preferences.showConsoleDrawer)
        }
        .sheet(isPresented: $showingCommandPalette) {
            CommandPaletteView(
                manager: manager,
                discovery: discovery,
                selection: $selection,
                isPresented: $showingCommandPalette
            )
        }
        .sheet(isPresented: $showingGitHubSheet) {
            GitHubAccountView(accountManager: githubAccount, manager: manager)
        }
        .sheet(isPresented: $showingHelpSheet) {
            HelpManualView()
        }
        .sheet(isPresented: $showingAISheet) {
            AISearchView(manager: manager)
        }
        .sheet(isPresented: $showingShellConfigSheet) {
            ShellConfigView(manager: manager)
        }
        .sheet(isPresented: $showingHealthSheet) {
            HealthScoreView(manager: manager)
        }
        .sheet(isPresented: $showingBrewfileImportSheet) {
            BrewfileImportView(manager: manager)
        }
        .detailModalOverlay(item: $deepLinkedPackage) { pkg in
            PackageDetailView(manager: manager, package: pkg, onDismiss: {
                deepLinkedPackage = nil
            })
        }
        .sheet(item: Binding(
            get: { uninstallCoordinator.pendingRequest },
            set: { newValue in
                if let newValue {
                    uninstallCoordinator.pendingRequest = newValue
                } else {
                    uninstallCoordinator.cancel()
                }
            }
        )) { request in
            BrewStoreUninstallPreviewView(
                request: request,
                onConfirm: {
                    uninstallCoordinator.confirm()
                },
                onConfirmSelection: { urls in
                    uninstallCoordinator.confirm(selectedResidualURLs: urls)
                },
                onCancel: uninstallCoordinator.cancel
            )
        }
        .sheet(item: Binding(
            get: { actionReviewCoordinator.pendingReview },
            set: { newValue in
                if let newValue {
                    actionReviewCoordinator.pendingReview = newValue
                } else {
                    actionReviewCoordinator.cancel()
                }
            }
        )) { request in
            BrewStoreActionReviewSheet(
                request: request,
                onConfirm: actionReviewCoordinator.confirm,
                onCancel: actionReviewCoordinator.cancel
            )
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .task {
            if manager.isAvailable {
                manager.refresh()
                manager.calculateStorageUsage()
                manager.checkAnalyticsState()
            }
        }
        .tint(themeManager.currentTheme.color)
    }

    private func dismissSecondarySheets() {
        if showingCommandPalette {
            showingCommandPalette = false
        }
        if showingGitHubSheet {
            showingGitHubSheet = false
        }
        if showingHelpSheet {
            showingHelpSheet = false
        }
        if showingAISheet {
            showingAISheet = false
        }
        if showingShellConfigSheet {
            showingShellConfigSheet = false
        }
        if showingHealthSheet {
            showingHealthSheet = false
        }
        if showingBrewfileImportSheet {
            showingBrewfileImportSheet = false
        }
    }

    private func handleIncomingURL(_ url: URL) {
        BrewStoreWindowManager.shared.showMainWindow()
        guard let route = BrewStoreURLSchemeRouter.parse(url: url) else { return }
        dismissSecondarySheets()
        switch route {
        case let .package(id, kind), let .install(id, kind):
            let targetPkg = manager.packages.first(where: { $0.id.lowercased() == id.lowercased() }) ??
                BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: kind ?? .formula)
            self.deepLinkedPackage = targetPkg
        case .search:
            selection = .discover
        case .allPackages:
            selection = .allPackages
        case .doctor:
            showingHealthSheet = true
        case .adopt:
            selection = .adoption
        case .security:
            showingHealthSheet = true
        case .settings:
            selection = .settings
        case .taps:
            selection = .taps
        case .services:
            selection = .services
        case .stacks:
            selection = .toolkits
        case .stories:
            selection = .stories
        case .updateAll:
            selection = .updates
            if !manager.isOperating {
                manager.upgradeAllPackages()
            }
        case .clean:
            manager.cleanup()
        case .blueprint:
            selection = .toolkits
        case let .quickInstall(ids):
            let pkgsToInstall = ids.map { id in
                manager.packages.first(where: { $0.id.lowercased() == id.lowercased() }) ??
                    BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: .formula)
            }
            guard !pkgsToInstall.isEmpty else { break }
            actionReviewCoordinator.requestInstall(packages: pkgsToInstall, manager: manager) {
                manager.batchPerform(packages: pkgsToInstall, action: .install)
            }
        case .open:
            if selection == nil {
                selection = .discover
            }
        }
    }

    private func retryRefresh() {
        manager.retryRefresh()
        discovery.load(force: true)
    }

    private func clearCacheAndRetry() {
        BrewStoreFastCacheEngine.clearCache()
        discovery.clearCache()
        manager.retryRefresh()
        discovery.load(force: true)
    }

    private func syncSidebarSelection(for mode: DiscoveryViewMode) {
        switch mode {
        case .spotlight:
            if selection != .discover {
                selection = .discover
            }
        case .allCatalog:
            if selection != .allPackages {
                selection = .allPackages
            }
        case .allApps:
            if selection != .allApps {
                selection = .allApps
            }
        case .allFormulae:
            if selection != .allFormulae {
                selection = .allFormulae
            }
        }
    }

    private func hubCollapsibleSection(for hub: BrewStoreHub, isExpanded: Binding<Bool>) -> some View {
        Section {
            if isExpanded.wrappedValue {
                ForEach(hub.subSections) { subSection in
                    subSidebarRow(for: subSection)
                }
            }
        } header: {
            hubHeaderRow(for: hub, isExpanded: isExpanded)
        }
    }

    private func hubHeaderRow(for hub: BrewStoreHub, isExpanded: Binding<Bool>) -> some View {
        let isStorefront = hub == .storefront
        return HStack(spacing: isStorefront ? 8 : 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: isStorefront ? 11 : 9.5, weight: isStorefront ? .heavy : .bold))
                    .frame(width: isStorefront ? 16 : 14, height: isStorefront ? 16 : 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded.wrappedValue ? "Collapse \(hub.rawValue)" : "Expand \(hub.rawValue)")

            Button {
                selection = hub.defaultSection
                if !isExpanded.wrappedValue {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.wrappedValue = true
                    }
                }
            } label: {
                HStack(spacing: isStorefront ? 7 : 6) {
                    Image(systemName: hub.icon)
                        .font(.system(size: isStorefront ? 15 : 11.5, weight: isStorefront ? .bold : .semibold))
                        .foregroundStyle(
                            isStorefront
                                ? (selection?.hub == .storefront ? Color.accentColor : Color.primary)
                                : (selection?.hub == hub ? Color.accentColor : .secondary)
                        )
                    Text(hub.rawValue)
                        .font(isStorefront ? .system(size: 15, weight: .bold) : .system(size: 11.5, weight: .bold))
                        .foregroundStyle(
                            isStorefront
                                ? (selection?.hub == .storefront ? Color.accentColor : Color.primary)
                                : (selection?.hub == hub ? Color.primary : .secondary)
                        )
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            hubSummaryBadge(for: hub)
        }
        .padding(.vertical, isStorefront ? 4 : 2)
        .padding(.top, isStorefront ? 2 : 4)
        .padding(.trailing, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "Sidebar.HubHeader.\(hub.rawValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "&", with: ""))"
        )
    }

    @ViewBuilder
    private func hubSummaryBadge(for hub: BrewStoreHub) -> some View {
        switch hub {
        case .storefront:
            let count = discovery.items.count
            if count > 0 {
                SidebarCountBadge(text: "\(count)")
            }
        case .myMac:
            let outdatedCount = manager.packages.filter(\.isOutdated).count
            if outdatedCount > 0 {
                SidebarCountBadge(
                    text: "\(outdatedCount)",
                    foregroundColor: .white,
                    backgroundColor: .orange,
                    isAccentOrProminent: true
                )
            } else {
                let count = manager.packages.filter(\.isInstalled).count
                if count > 0 {
                    SidebarCountBadge(text: "\(count)")
                }
            }
        case .environment:
            let errorCount = manager.services.filter(\.isError).count
            let running = manager.services.filter(\.isRunning).count
            if errorCount > 0 {
                SidebarCountBadge(
                    text: "\(errorCount)",
                    foregroundColor: .white,
                    backgroundColor: .red,
                    isAccentOrProminent: true,
                    leadingDotColor: .white
                )
            } else if running > 0 {
                SidebarCountBadge(
                    text: "\(running)",
                    foregroundColor: .green,
                    backgroundColor: Color.green.opacity(0.12),
                    isAccentOrProminent: true,
                    leadingDotColor: .green
                )
            }
        case .health, .settings:
            EmptyView()
        }
    }

    private func subSidebarRow(for section: BrewStoreSection) -> some View {
        sidebarRow(for: section)
            .padding(.leading, 8)
            .padding(.trailing, 12)
    }

    private func sidebarRow(for section: BrewStoreSection) -> some View {
        HStack(spacing: 8) {
            Label {
                Text(section.rawValue)
                    .font(.system(size: 13, weight: .regular))
            } icon: {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 4)
            sidebarBadge(for: section)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selection = section
        }
        .contextMenu {
            if section == .updates {
                let outdated = manager.packages.filter(\.isOutdated)
                if !outdated.isEmpty {
                    Button {
                        BrewStoreActionReviewCoordinator.shared.requestUpgrade(packages: outdated, manager: manager) {
                            manager.upgradeAllPackages()
                        }
                    } label: {
                        Label("Upgrade All (\(outdated.count))", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Divider()
                }
                Button {
                    manager.retryRefresh()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
            } else if section == .services {
                let runningServices = manager.services.filter(\.isRunning)
                Button {
                    manager.batchPerform(services: runningServices, action: .restart)
                } label: {
                    Label("Restart Running Services (\(runningServices.count))", systemImage: "arrow.counterclockwise")
                }
                .disabled(runningServices.isEmpty)
            } else if section == .installed {
                Button {
                    manager.cleanup()
                } label: {
                    Label("Clean Disk Cache (brew cleanup)", systemImage: "trash")
                }
            }
        }
        .tag(section)
        .accessibilityIdentifier("Sidebar.\(section.rawValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "&", with: ""))")
    }

    @ViewBuilder
    private func sidebarBadge(for section: BrewStoreSection) -> some View {
        switch section {
        case .allPackages:
            let count = discovery.items.count
            if count > 0 {
                SidebarCountBadge(text: "\(count)")
            }
        case .allApps:
            let count = discovery.items.filter { $0.kind == .cask }.count
            if count > 0 {
                SidebarCountBadge(text: "\(count)")
            }
        case .allFormulae:
            let count = discovery.items.filter { $0.kind == .formula }.count
            if count > 0 {
                SidebarCountBadge(text: "\(count)")
            }
        case .updates:
            let outdated = manager.packages.filter(\.isOutdated)
            if !outdated.isEmpty {
                let summary = outdated.prefix(5).map { "\($0.name) (\($0.installedVersion ?? "") -> \($0.version))" }.joined(separator: "\n• ")
                let moreText = outdated.count > 5 ? "\n...and \(outdated.count - 5) more." : ""
                SidebarCountBadge(
                    text: "\(outdated.count)",
                    foregroundColor: .white,
                    backgroundColor: .orange,
                    isAccentOrProminent: true
                )
                .help("\(outdated.count) Update\(outdated.count == 1 ? "" : "s") Available:\n• \(summary)\(moreText)\n\nShortcut: ⌥⌘U to upgrade all.")
            }
        case .installed:
            let count = manager.packages.filter(\.isInstalled).count
            if count > 0 {
                SidebarCountBadge(text: "\(count)")
            }
        case .adoption:
            let count = BrewStoreAppAdoptionManager.shared.adoptableApps.count
            if count > 0 {
                SidebarCountBadge(
                    text: "\(count)",
                    foregroundColor: .blue,
                    backgroundColor: Color.blue.opacity(0.12),
                    isAccentOrProminent: true
                )
            }
        case .wishlist:
            let count = BrewStoreWishlistManager.shared.wishlistIDs.count
            if count > 0 {
                SidebarCountBadge(text: "\(count)")
            }
        case .services:
            let errorCount = manager.services.filter(\.isError).count
            let running = manager.services.filter(\.isRunning).count
            if errorCount > 0 {
                SidebarCountBadge(
                    text: "\(errorCount)",
                    foregroundColor: .white,
                    backgroundColor: .red,
                    isAccentOrProminent: true,
                    leadingDotColor: .white
                )
                .accessibilityLabel("\(errorCount) failed")
                .help("\(errorCount) service\(errorCount == 1 ? "" : "s") in error/failed state.")
            } else if running > 0 {
                SidebarCountBadge(
                    text: "\(running)",
                    foregroundColor: .green,
                    backgroundColor: Color.green.opacity(0.12),
                    isAccentOrProminent: true,
                    leadingDotColor: .green
                )
                .accessibilityLabel("\(running) running")
                .help("\(running) background service\(running == 1 ? "" : "s") running.")
            }
        case .taps:
            let count = manager.taps.count
            if count > 0 {
                SidebarCountBadge(text: "\(count)")
            }
        case .creator:
            if githubAccount.isAuthenticated {
                let tapCount = BrewStoreCreatorRepoManager.shared.taps.count
                if tapCount > 0 {
                    SidebarCountBadge(
                        text: "\(tapCount)",
                        foregroundColor: Color.accentColor,
                        backgroundColor: Color.accentColor.opacity(0.12),
                        isAccentOrProminent: true
                    )
                }
            }
        default:
            EmptyView()
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if manager.isOperating {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(manager.activeOperationTitle ?? "Operating…")
                            .font(.caption2.bold())
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Button("Cancel", role: .destructive, action: manager.cancelCurrentOperation)
                            .buttonStyle(.borderless)
                            .font(.caption2)
                    }
                    if !manager.statusMessage.isEmpty {
                        Text(manager.statusMessage)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Multi-Provider Git Account Profile Tile
            Button {
                showingGitHubSheet = true
            } label: {
                HStack(spacing: 10) {
                    if let active = gitService.activeAccount {
                        if let avatar = active.avatarURL, let url = URL(string: avatar) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Image(systemName: active.provider.iconName)
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: active.provider.iconName)
                                .font(.title3)
                                .foregroundStyle(.tint)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(active.login)")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("\(active.provider.displayName) · Cloud Sync")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if githubAccount.isAuthenticated {
                        if let profile = githubAccount.profile, let avatar = profile.avatar_url, let url = URL(string: avatar) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Image(systemName: "person.crop.circle.fill")
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(githubAccount.profile?.login ?? "user")")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("\(githubAccount.rateLimitRemaining) req/hr")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Sign In with Git Services")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("Cloud Backup & Sync")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Sidebar.ProfileGitHub")

            HStack(spacing: 6) {
                Circle()
                    .fill(manager.isAvailable ? .green : .orange)
                    .frame(width: 6, height: 6)
                Text(manager.isAvailable ? "Homebrew active" : "Homebrew required")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 4)

                if let prefix = manager.brewPrefix {
                    Text(prefix.hasPrefix("/opt") ? "Apple Silicon" : "Intel")
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                        .fixedSize(horizontal: true, vertical: false)
                }

                Button {
                    manager.cleanup()
                } label: {
                    Image(systemName: "trash.circle")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Reclaim Disk Space (brew cleanup)")
                .disabled(manager.isOperating)
                .accessibilityIdentifier("Sidebar.QuickCleanupButton")

                Button {
                    selection = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundStyle(selection == .settings ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
                .accessibilityIdentifier("Sidebar.SettingsButton")
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .overlay(alignment: .top) {
            Divider()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.isOperating)
    }
}

// MARK: - Sidebar Split View Manager & Fixed Non-Draggable Sizing

@MainActor
final class BrewStoreSplitViewManager: ObservableObject {
    static let shared = BrewStoreSplitViewManager()

    /// The exact fixed width calculated so all sidebar items and badges comfortably fit with zero truncation and zero wasted blank space.
    static let fixedSidebarWidth: CGFloat = 248.0

    /// Backward compatibility aliases for existing callers and tests
    static var optimalSidebarWidth: CGFloat {
        fixedSidebarWidth
    }

    static var maxSidebarWidth: CGFloat {
        fixedSidebarWidth
    }

    static var minSidebarWidth: CGFloat {
        fixedSidebarWidth
    }

    private weak var splitView: NSSplitView?

    private init() {}

    func configure(splitView: NSSplitView) {
        self.splitView = splitView

        // Swizzle NSSplitViewController's divider effective rect so divider 0 has zero hit area
        NSSplitViewController.swizzleEffectiveRectIfNeeded()

        // Lock sidebar item to the exact fixed width and disable drag collapse
        if let splitVC = splitView.delegate as? NSSplitViewController,
           let item = splitVC.splitViewItems.first {
            item.canCollapse = false
            item.minimumThickness = Self.fixedSidebarWidth
            item.maximumThickness = Self.fixedSidebarWidth
            item.holdingPriority = NSLayoutConstraint.Priority(1000)
        }

        // Lock divider to the fixed snug width
        splitView.setPosition(Self.fixedSidebarWidth, ofDividerAt: 0)
    }

    func snapToOptimalWidthOrToggle(splitView customSplitView: NSSplitView? = nil) {
        guard let splitView = customSplitView ?? self.splitView ?? NSApp.keyWindow?.contentView?.findFirstSplitView() ?? NSApp.mainWindow?.contentView?.findFirstSplitView() else {
            return
        }
        splitView.setPosition(Self.fixedSidebarWidth, ofDividerAt: 0)
    }
}

// MARK: - NSSplitViewController Swizzling (Disables Divider Dragging)

extension NSSplitViewController {
    private static var hasSwizzledEffectiveRect = false

    static func swizzleEffectiveRectIfNeeded() {
        guard !hasSwizzledEffectiveRect else { return }
        hasSwizzledEffectiveRect = true

        let originalSelector = #selector(NSSplitViewDelegate.splitView(_:effectiveRect:forDrawnRect:ofDividerAt:))
        let swizzledSelector = #selector(NSSplitViewController.brewstore_splitView(_:effectiveRect:forDrawnRect:ofDividerAt:))

        if let originalMethod = class_getInstanceMethod(NSSplitViewController.self, originalSelector),
           let swizzledMethod = class_getInstanceMethod(NSSplitViewController.self, swizzledSelector) {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    @objc func brewstore_splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        if dividerIndex == 0, splitView.isVertical {
            // Zero hit rect disables mouse dragging and cursor change on the sidebar divider
            return .zero
        }
        return self.brewstore_splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
    }
}

// MARK: - Split View Finder NSViewRepresentable

struct BrewStoreSplitViewAccessor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        SplitViewFinderView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private class SplitViewFinderView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachToSplitView()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attachToSplitView()
        }

        private func attachToSplitView() {
            guard let window = self.window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window, self != nil else { return }
                if let splitView = window.contentView?.findFirstSplitView() {
                    BrewStoreSplitViewManager.shared.configure(splitView: splitView)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak window] in
                        if let splitView = window?.contentView?.findFirstSplitView() {
                            BrewStoreSplitViewManager.shared.configure(splitView: splitView)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sidebar Outline View Delegate Manager (Prevents Group Header Selection)

@MainActor
final class BrewStoreSidebarOutlineManager: NSObject, NSOutlineViewDelegate {
    static let shared = BrewStoreSidebarOutlineManager()
    private weak var outlineView: NSOutlineView?
    private weak var originalDelegate: NSOutlineViewDelegate?

    func attach(to outlineView: NSOutlineView) {
        guard self.outlineView !== outlineView else { return }
        if let currentDelegate = outlineView.delegate, currentDelegate !== self {
            self.originalDelegate = currentDelegate
        } else if self.originalDelegate === self {
            self.originalDelegate = nil
        }
        self.outlineView = outlineView
        outlineView.delegate = self

        NotificationCenter.default.removeObserver(self, name: NSOutlineView.selectionDidChangeNotification, object: outlineView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChange(_:)),
            name: NSOutlineView.selectionDidChangeNotification,
            object: outlineView
        )
    }

    func isGroupOrHeaderItem(_ item: Any, in outlineView: NSOutlineView) -> Bool {
        if outlineView.isExpandable(item) {
            return true
        }
        if let orig = originalDelegate, orig !== self, orig.responds(to: #selector(NSOutlineViewDelegate.outlineView(_:isGroupItem:))) {
            return orig.outlineView?(outlineView, isGroupItem: item) ?? false
        }
        return false
    }

    @objc private func handleSelectionChange(_ notification: Notification) {
        guard let outline = notification.object as? NSOutlineView else { return }
        let selectedIndexes = outline.selectedRowIndexes
        var rowsToDeselect = IndexSet()
        for row in selectedIndexes {
            if let item = outline.item(atRow: row), isGroupOrHeaderItem(item, in: outline) {
                rowsToDeselect.insert(row)
            }
        }
        if !rowsToDeselect.isEmpty {
            for row in rowsToDeselect {
                outline.deselectRow(row)
            }
        }
    }

    @objc func tableViewColumnDidResize(_: Notification) {}
    @objc func outlineViewColumnDidResize(_: Notification) {}

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSOutlineViewDelegate.outlineView(_:shouldSelectItem:)) {
            return true
        }
        if aSelector == #selector(NSOutlineViewDelegate.outlineView(_:selectionIndexesForProposedSelection:)) {
            return true
        }
        if super.responds(to: aSelector) {
            return true
        }
        guard let orig = originalDelegate, orig !== self else {
            return false
        }
        return orig.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        guard let orig = originalDelegate, orig !== self else {
            return nil
        }
        if orig.responds(to: aSelector) {
            return orig
        }
        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if isGroupOrHeaderItem(item, in: outlineView) {
            return false
        }
        if let orig = originalDelegate, orig !== self, orig.responds(to: #selector(NSOutlineViewDelegate.outlineView(_:shouldSelectItem:))) {
            return orig.outlineView?(outlineView, shouldSelectItem: item) ?? true
        }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        var allowed = IndexSet()
        for row in proposedSelectionIndexes {
            if let item = outlineView.item(atRow: row) {
                if !isGroupOrHeaderItem(item, in: outlineView) {
                    allowed.insert(row)
                }
            } else {
                allowed.insert(row)
            }
        }
        if let orig = originalDelegate, orig !== self, orig.responds(to: #selector(NSOutlineViewDelegate.outlineView(_:selectionIndexesForProposedSelection:))) {
            return orig.outlineView?(outlineView, selectionIndexesForProposedSelection: allowed) ?? allowed
        }
        return allowed
    }
}

struct SidebarCountBadge: View {
    let text: String
    var foregroundColor: Color = .secondary
    var backgroundColor: Color = Color.secondary.opacity(0.12)
    var isAccentOrProminent: Bool = false
    var leadingDotColor: Color?

    var body: some View {
        HStack(spacing: 3) {
            if let leadingDotColor {
                Circle()
                    .fill(leadingDotColor)
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(.system(size: 10.5, weight: isAccentOrProminent ? .bold : .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(minHeight: 18)
        .background(backgroundColor, in: Capsule())
        .frame(minWidth: 28, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private extension NSView {
    func findFirstSplitView() -> NSSplitView? {
        if let split = self as? NSSplitView {
            return split
        }
        for sub in subviews {
            if let found = sub.findFirstSplitView() {
                return found
            }
        }
        return nil
    }

    func findFirstOutlineView() -> NSOutlineView? {
        if let outline = self as? NSOutlineView {
            return outline
        }
        for sub in subviews {
            if let found = sub.findFirstOutlineView() {
                return found
            }
        }
        return nil
    }
}
