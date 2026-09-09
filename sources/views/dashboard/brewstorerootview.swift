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
                        sidebarRow(for: .settings)
                    } header: {
                        Text("System")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
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
            .overlay(alignment: .trailing) {
                // Interactive hit area on the trailing separation edge of the sidebar for instant double-click
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        BrewStoreSplitViewManager.shared.snapToOptimalWidthOrToggle()
                    }
            }
            .frame(minWidth: BrewStoreSplitViewManager.minSidebarWidth, idealWidth: BrewStoreSplitViewManager.optimalSidebarWidth, maxWidth: BrewStoreSplitViewManager.maxSidebarWidth)
            .navigationSplitViewColumnWidth(min: BrewStoreSplitViewManager.minSidebarWidth, ideal: BrewStoreSplitViewManager.optimalSidebarWidth, max: BrewStoreSplitViewManager.maxSidebarWidth)
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

                    Button {
                        showingBrewfileImportSheet = true
                    } label: {
                        Label("Import Brewfile", systemImage: "doc.badge.plus")
                    }
                    .help("Import software bundle from Brewfile")
                    .accessibilityIdentifier("Toolbar.ImportBrewfile")

                    Button {
                        showingHealthSheet = true
                    } label: {
                        Label("Health Score", systemImage: "heart.text.square")
                    }
                    .help("Homebrew Health & Optimizer")
                    .accessibilityIdentifier("Toolbar.HealthScore")

                    Button {
                        showingAISheet = true
                    } label: {
                        Label("AI Assistant", systemImage: "wand.and.stars")
                    }
                    .help("AI Package Assistant")
                    .accessibilityIdentifier("Toolbar.AIAssistant")

                    Button {
                        showingShellConfigSheet = true
                    } label: {
                        Label("Shell Setup", systemImage: "terminal")
                    }
                    .help("Shell Environment Assistant")
                    .accessibilityIdentifier("Toolbar.ShellSetup")

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

                    Button {
                        showingHelpSheet = true
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .help("Help Manual (⌘?)")
                    .accessibilityIdentifier("Toolbar.Help")
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
                onConfirm: uninstallCoordinator.confirm,
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

    private func handleIncomingURL(_ url: URL) {
        guard let route = BrewStoreURLSchemeRouter.parse(url: url) else { return }
        switch route {
        case let .package(id, kind), let .install(id, kind):
            let targetPkg = manager.packages.first(where: { $0.id.lowercased() == id.lowercased() }) ??
                BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: kind ?? .formula)
            self.deepLinkedPackage = targetPkg
        case .search:
            selection = .discover
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
        case .spotlight, .allCatalog:
            if selection != .discover {
                selection = .discover
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
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 14, height: 14)
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
                HStack(spacing: 6) {
                    Image(systemName: hub.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection?.hub == hub ? Color.accentColor : .secondary)
                    Text(hub.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection?.hub == hub ? Color.primary : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            hubSummaryBadge(for: hub)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Sidebar.HubHeader.\(hub.rawValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "&", with: ""))")
    }

    @ViewBuilder
    private func hubSummaryBadge(for hub: BrewStoreHub) -> some View {
        switch hub {
        case .storefront:
            let count = discovery.items.count
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
        case .myMac:
            let outdatedCount = manager.packages.filter(\.isOutdated).count
            if outdatedCount > 0 {
                Text("\(outdatedCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
            } else {
                let count = manager.packages.filter(\.isInstalled).count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }
        case .environment:
            let running = manager.services.filter(\.isRunning).count
            if running > 0 {
                HStack(spacing: 3) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("\(running)")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.12), in: Capsule())
            }
        case .health, .settings:
            EmptyView()
        }
    }

    private func subSidebarRow(for section: BrewStoreSection) -> some View {
        sidebarRow(for: section)
            .padding(.leading, 8)
    }

    private func sidebarRow(for section: BrewStoreSection) -> some View {
        HStack(spacing: 8) {
            Label(section.rawValue, systemImage: section.icon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            Spacer(minLength: 6)
            switch section {
            case .allApps:
                let count = discovery.items.filter { $0.kind == .cask }.count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            case .allFormulae:
                let count = discovery.items.filter { $0.kind == .formula }.count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            case .updates:
                let outdatedCount = manager.packages.filter(\.isOutdated).count
                if outdatedCount > 0 {
                    Text("\(outdatedCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                }
            case .installed:
                let count = manager.packages.filter(\.isInstalled).count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            case .adoption:
                let count = BrewStoreAppAdoptionManager.shared.adoptableApps.count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            case .wishlist:
                let count = BrewStoreWishlistManager.shared.wishlistIDs.count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            case .services:
                let running = manager.services.filter(\.isRunning).count
                if running > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("\(running) running").font(.caption2.bold()).foregroundStyle(.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .accessibilityLabel("\(running) running")
                }
            case .taps:
                let count = manager.taps.count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            case .creator:
                if githubAccount.isAuthenticated {
                    let tapCount = BrewStoreCreatorRepoManager.shared.taps.count
                    if tapCount > 0 {
                        Text("\(tapCount) taps")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            default:
                EmptyView()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selection = section
        }
        .tag(section)
        .accessibilityIdentifier("Sidebar.\(section.rawValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "&", with: ""))")
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

// MARK: - Sidebar Split View Manager & Double-Click Auto-Fit

@MainActor
final class BrewStoreSplitViewManager: ObservableObject {
    static let shared = BrewStoreSplitViewManager()

    /// The exact optimal width calculated for all sidebar items and footer elements
    /// Designed so everything just fits with zero wasted blank space.
    static let optimalSidebarWidth: CGFloat = 226.0
    static let maxSidebarWidth: CGFloat = 228.0
    static let minSidebarWidth: CGFloat = 180.0

    private var eventMonitor: Any?
    private weak var splitView: NSSplitView?

    private init() {}

    func configure(splitView: NSSplitView) {
        self.splitView = splitView

        // Enable collapse on the sidebar split view item if managed by NSSplitViewController
        if let splitVC = splitView.delegate as? NSSplitViewController,
           let item = splitVC.splitViewItems.first {
            item.canCollapse = true
            item.minimumThickness = Self.minSidebarWidth
            item.maximumThickness = Self.maxSidebarWidth
            item.holdingPriority = NSLayoutConstraint.Priority.defaultLow
        }

        // Clamp divider to optimal snug width where all items just fit without blanks
        splitView.setPosition(Self.optimalSidebarWidth, ofDividerAt: 0)

        // Install local mouse double-click monitor on the divider
        installDividerMonitorIfNeeded(splitView: splitView)
    }

    private func installDividerMonitorIfNeeded(splitView: NSSplitView) {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak splitView] event in
            guard let self,
                  event.clickCount == 2
            else {
                return event
            }

            // Obtain split view reference (cached or retrieved on demand)
            guard let targetSplit = splitView ?? self.splitView ?? event.window?.contentView?.findFirstSplitView(),
                  let window = targetSplit.window,
                  event.window == window,
                  targetSplit.isVertical,
                  let sidebarView = targetSplit.subviews.first
            else {
                return event
            }

            let locationInSplit = targetSplit.convert(event.locationInWindow, from: nil)
            let dividerX = sidebarView.frame.maxX
            let hitMargin: CGFloat = 12.0 // 24pt interactive hit region centered on the divider line

            let isNearDivider = abs(locationInSplit.x - dividerX) <= hitMargin
            let isWithinVerticalBounds = locationInSplit.y >= 0 && locationInSplit.y <= targetSplit.bounds.height

            if isNearDivider, isWithinVerticalBounds {
                self.snapToOptimalWidthOrToggle(splitView: targetSplit)
                return nil // Consumed double click
            }

            return event
        }
    }

    func snapToOptimalWidthOrToggle(splitView customSplitView: NSSplitView? = nil) {
        guard let splitView = customSplitView ?? self.splitView ?? NSApp.keyWindow?.contentView?.findFirstSplitView() ?? NSApp.mainWindow?.contentView?.findFirstSplitView(),
              let sidebarView = splitView.subviews.first
        else {
            NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            return
        }

        let currentWidth = sidebarView.frame.width
        let isCollapsed = splitView.isSubviewCollapsed(sidebarView) || currentWidth < 30.0
        let optimal = Self.optimalSidebarWidth

        if isCollapsed {
            // If collapsed, expand directly to optimal width
            if let splitVC = splitView.delegate as? NSSplitViewController {
                splitVC.toggleSidebar(nil)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                splitView.animator().setPosition(optimal, ofDividerAt: 0)
            }
        } else if abs(currentWidth - optimal) > 4.0 {
            // User had dragged it wider or narrower: snap directly to optimal content width!
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                splitView.animator().setPosition(optimal, ofDividerAt: 0)
            }
        } else {
            // Already at optimal width: collapse it!
            if let splitVC = splitView.delegate as? NSSplitViewController {
                splitVC.toggleSidebar(nil)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    splitView.animator().setPosition(0, ofDividerAt: 0)
                }
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
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
