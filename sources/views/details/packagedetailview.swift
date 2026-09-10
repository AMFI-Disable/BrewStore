import AppKit
import SwiftUI

struct PackageDetailView: View {
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage
    @ObservedObject var preferences = BrewStorePreferences.shared

    @State private var dependents: [String] = []
    @State private var isLoadingDependents = false
    @State private var removalPlan: BrewStoreRemovalPlan?
    @State private var isScanningRemoval = false
    @State private var showingRemoval = false
    @State private var removalError: String?
    @State private var dependencyTree: String?
    @State private var showingDependencyTree = false
    @State private var showingVisualGraph = false

    // Collapsible Disclosures State
    @State private var isVersionsExpanded = true
    @State private var isDependenciesExpanded = false
    @State private var isDependentsExpanded = false
    @State private var isCleanerExpanded = false
    @State private var isCaveatsExpanded = false
    @State private var isSecurityExpanded = false
    @State private var showingAdvancedInstallSheet = false
    @State private var showingSecurityApprovalSheet = false
    @State private var isAnalyticsExpanded = false

    @StateObject private var securityInspector = BrewStoreSecurityInspector()
    @StateObject private var storageInspector = BrewStoreAppStorageInspector()
    @StateObject private var analyticsManager = BrewStoreAnalyticsManager.shared
    @StateObject private var shellAssistant = BrewStoreShellConfigAssistant()
    @ObservedObject private var pinningManager = BrewStorePackagePinningManager.shared
    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared
    @Environment(\.dismiss) private var dismiss
    var onDismiss: (() -> Void)?
    @State private var packageAnalytics: PackageInstallAnalytics?
    @State private var selectedDependencyPackage: BrewStorePackage?
    @State private var caveatAppliedSuccess = false

    private var currentPackage: BrewStorePackage {
        manager.packages.first { $0.id == package.id && $0.kind == package.kind } ?? package
    }

    init(manager: HomebrewManager, package: BrewStorePackage, onDismiss: (() -> Void)? = nil) {
        self.manager = manager
        self.package = package
        self.onDismiss = onDismiss
        let initialAnalytics = BrewStoreAnalyticsManager.shared.cachedOrBaseline(packageID: package.id, kind: package.kind)
        _packageAnalytics = State(initialValue: initialAnalytics)
    }

    private func handleDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var isOperatingThisPackage: Bool {
        guard manager.isOperating else { return false }
        if let title = manager.activeOperationTitle {
            return title.localizedCaseInsensitiveContains(currentPackage.name) ||
                title.localizedCaseInsensitiveContains(currentPackage.id)
        }
        return false
    }

    private var installedAppURL: URL? {
        guard currentPackage.kind == .cask else { return nil }
        let names = currentPackage.applicationNames.isEmpty ? [currentPackage.name] : currentPackage.applicationNames
        return BrewStoreAppIconResolver.localAppURL(for: names)
    }

    private var installedAppIcon: NSImage? {
        guard currentPackage.kind == .cask else { return nil }
        let names = currentPackage.applicationNames.isEmpty ? [currentPackage.name] : currentPackage.applicationNames
        return BrewStoreAppIconResolver.localAppIcon(for: names)
    }

    private var siblings: [BrewStorePackage] {
        manager.fetchSiblingVersions(for: currentPackage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerView

                // Inline Streaming Operation Drawer
                if isOperatingThisPackage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            HStack(spacing: 6) {
                                Text(manager.activeOperationTitle ?? "Processing…")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                if let live = BrewStoreUpdateEstimator.liveRemainingTimeString(manager: manager) {
                                    Text(live)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Spacer()
                            Button("Cancel", role: .destructive, action: manager.cancelCurrentOperation)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }

                        if !manager.statusMessage.isEmpty {
                            ScrollView {
                                Text(manager.statusMessage)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 75)
                            .padding(8)
                            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Divider()

                keyMetricsBar

                if let pick = BrewStoreEditorialPick.pick(for: currentPackage.id) {
                    editorialPickCard(pick: pick)
                }

                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("About").font(.headline)
                    if !currentPackage.description.isEmpty {
                        Text(currentPackage.description)
                            .font(.body)
                            .lineSpacing(4)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }

                // Collapsible Panels
                VStack(spacing: 8) {
                    if siblings.count > 1 {
                        DisclosureGroup(isExpanded: $isVersionsExpanded) {
                            versionSwitcherContent(siblings: siblings)
                                .padding(.top, 6)
                        } label: {
                            Label("Versions (\(siblings.count) Installed)", systemImage: "arrow.triangle.swap")
                                .font(.headline)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
                    }

                    if !currentPackage.dependencies.isEmpty {
                        DisclosureGroup(isExpanded: $isDependenciesExpanded) {
                            dependenciesContent
                                .padding(.top, 6)
                        } label: {
                            Label("Dependencies (\(currentPackage.dependencies.count))", systemImage: "point.3.connected.trianglepath.dotted")
                                .font(.headline)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
                    }

                    if !dependents.isEmpty {
                        DisclosureGroup(isExpanded: $isDependentsExpanded) {
                            dependentsContent
                                .padding(.top, 6)
                        } label: {
                            Label("Used By (\(dependents.count) Packages)", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
                    }

                    if preferences.enableAppCleaner, currentPackage.isInstalled {
                        DisclosureGroup(isExpanded: $isCleanerExpanded) {
                            appStorageInspectorContent
                                .padding(.top, 6)
                        } label: {
                            Label("Storage & Cache Breakdown", systemImage: "internaldrive.fill")
                                .font(.headline)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
                    }

                    if let caveats = currentPackage.caveats, !caveats.isEmpty {
                        DisclosureGroup(isExpanded: $isCaveatsExpanded) {
                            caveatsContent(caveats: caveats)
                                .padding(.top, 6)
                        } label: {
                            Label("Configuration & Shell Setup", systemImage: "terminal")
                                .font(.headline)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
                    }

                    if currentPackage.isInstalled {
                        DisclosureGroup(isExpanded: $isSecurityExpanded) {
                            securityInspectorContent
                                .padding(.top, 6)
                        } label: {
                            Label("Security, Architecture & Gatekeeper", systemImage: "shield.lefthalf.filled")
                                .font(.headline)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
                    }
                }

                // Similar & Alternative Tools Carousel
                similarToolsCarousel

                let requiredPerms = TCCPermissionManager.shared.detectPermissions(for: currentPackage)
                if !requiredPerms.isEmpty {
                    HStack {
                        Label("\(requiredPerms.count) System Permission(s) Required", systemImage: "hand.raised.square.on.square.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                        Spacer()
                        Button("Review Approvals") {
                            showingSecurityApprovalSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .sheet(isPresented: $showingSecurityApprovalSheet) {
                        SecurityApprovalSheet(package: currentPackage, permissions: requiredPerms)
                    }
                }

                // Popularity & Install Activity (Collapsed by default)
                DisclosureGroup(isExpanded: $isAnalyticsExpanded) {
                    analyticsDashboardSection
                        .padding(.top, 6)
                } label: {
                    Label("Install Trends & Popularity", systemImage: "chart.bar.xaxis")
                        .font(.headline)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.08), lineWidth: 1))

                // App Store Information Table
                informationTable

                if !manager.statusMessage.isEmpty {
                    Text(manager.statusMessage).font(.callout).foregroundStyle(.secondary)
                }
                if let error = manager.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        if manager.lastOperationRequiresElevation {
                            Button {
                                let action: PackageAction = currentPackage.isInstalled ? .upgrade : .install
                                manager.performElevated(package: currentPackage, action: action)
                            } label: {
                                Label("Rerun with Administrator Privileges", systemImage: "lock.shield.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                // Blank space tap area at bottom: clicking empty space returns to previous view
                Color.clear
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleDismiss()
                    }
            }
            .padding(18)
        }
        .brewStorePackageContextMenu(package: currentPackage, manager: manager)
        .task {
            packageAnalytics = await analyticsManager.fetchAnalytics(packageID: currentPackage.id, kind: currentPackage.kind)
            if currentPackage.isInstalled {
                securityInspector.inspect(package: currentPackage, manager: manager)
                storageInspector.inspect(package: currentPackage)
            }
            if currentPackage.kind == .formula, currentPackage.isInstalled {
                isLoadingDependents = true
                dependents = await manager.fetchDependents(for: currentPackage)
                isLoadingDependents = false
            }
        }
        .sheet(isPresented: $showingRemoval) {
            if let plan = removalPlan {
                RemovalPreviewView(manager: manager, package: currentPackage, plan: plan)
            }
        }
        .sheet(isPresented: $showingVisualGraph) {
            DependencyGraphView(manager: manager, rootPackage: currentPackage)
        }
        .sheet(isPresented: $showingAdvancedInstallSheet) {
            AdvancedInstallView(manager: manager, package: currentPackage)
        }
        .detailModalOverlay(item: $selectedDependencyPackage) { depPkg in
            PackageDetailView(manager: manager, package: depPkg, onDismiss: {
                selectedDependencyPackage = nil
            })
        }
    }

    // MARK: - App Store Header View

    @ViewBuilder
    private var headerView: some View {
        let isWishlisted = wishlistManager.isWishlisted(id: currentPackage.id)

        VStack(alignment: .leading, spacing: 14) {
            // Navigation Bar with Back and Close affordances
            HStack {
                Button {
                    handleDismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back (Esc or ⌘[)")
                .accessibilityIdentifier("PackageDetail.BackButton")

                Spacer()

                Button {
                    handleDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
                .accessibilityIdentifier("PackageDetail.CloseButton")
            }
            .padding(.bottom, 2)

            HStack(alignment: .center, spacing: 16) {
                if let icon = installedAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
                } else {
                    Image(systemName: currentPackage.kind == .cask ? "app.fill" : "terminal.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(currentPackage.name)
                            .font(.title.bold())
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if currentPackage.isInstalled, pinningManager.isPinned(packageID: currentPackage.id) {
                            HStack(spacing: 4) {
                                Image(systemName: "pin.fill")
                                Text("Pinned")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                        }

                        if let badge = TrendingRankingsManager.badge(for: currentPackage) {
                            HStack(spacing: 4) {
                                Image(systemName: badge.icon)
                                Text(badge.title)
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(currentPackage.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    Text(currentPackage.displayKind).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()
            }

            // Primary Action Buttons Bar
            HStack(spacing: 8) {
                AppStoreActionButton(manager: manager, package: currentPackage, size: .regular)

                if currentPackage.isInstalled {
                    let isPinned = pinningManager.isPinned(packageID: currentPackage.id)
                    let isPinning = pinningManager.isPinningInProgress(packageID: currentPackage.id)
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            pinningManager.togglePin(package: currentPackage, manager: manager)
                        }
                    } label: {
                        if isPinning {
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.mini)
                                Text(isPinned ? "Unpinning…" : "Pinning…")
                            }
                        } else {
                            Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(manager.isOperating || isPinning)
                    .accessibilityIdentifier("PackageDetail.PinButton")
                    .help(isPinned ? "Unpin version to allow updates" : "Pin version to prevent automatic updates")
                }

                if currentPackage.isOutdated {
                    let est = BrewStoreUpdateEstimator.estimate(for: currentPackage)
                    HStack(spacing: 4) {
                        Image(systemName: "timer").font(.caption2)
                        Text("~\(est.formattedEstimate)")
                            .font(.caption2.bold().monospaced())
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12), in: Capsule())

                    if BrewStoreVersionComparator.isMajorUpgrade(installed: currentPackage.installedVersion, latest: currentPackage.version) {
                        let summary = BrewStoreVersionComparator.majorUpgradeSummary(installed: currentPackage.installedVersion, latest: currentPackage.version) ?? "Major Bump"
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                            Text("Major Upgrade (\(summary))")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .help("Major version updates may contain breaking changes or require database migrations.")
                    }
                }

                Button {
                    showingAdvancedInstallSheet = true
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    wishlistManager.toggleWishlist(id: currentPackage.id)
                } label: {
                    Image(systemName: isWishlisted ? "star.fill" : "star")
                        .foregroundStyle(isWishlisted ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help(isWishlisted ? "Unstar (Remove from Wishlist)" : "Star (Add to Wishlist)")

                if let url = URL(string: currentPackage.homepage), !currentPackage.homepage.isEmpty {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Share Package")
                }

                Spacer()
            }
        }
    }

    // MARK: - Key Metrics Bar

    @ViewBuilder
    private var keyMetricsBar: some View {
        let footprint = BrewStoreBottleFootprintEstimator.estimateFootprint(for: currentPackage)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 8)], spacing: 8) {
            metricCard(title: "Type", value: currentPackage.kind == .cask ? "macOS App" : "CLI Binary", icon: currentPackage.kind == .cask ? "app.fill" : "terminal.fill")
            metricCard(title: "Download size", value: "~" + footprint.formattedDownloadSize, icon: "arrow.down.circle")
            metricCard(title: "Disk space", value: "~" + footprint.formattedFootprintSize, icon: "internaldrive")
            metricCard(title: "Status", value: currentPackage.isInstalled ? (currentPackage.isOutdated ? "Update" : "Installed") : "Available", icon: currentPackage.isInstalled ? "checkmark.circle.fill" : "circle")
            metricCard(title: "Installs (30d)", value: packageAnalytics?.formatted30d ?? "—", icon: "calendar")
            metricCard(title: "Installs (1 yr)", value: packageAnalytics?.formatted365d ?? "—", icon: "chart.line.uptrend.xyaxis")
            if currentPackage.isOutdated {
                let est = BrewStoreUpdateEstimator.estimate(for: currentPackage)
                metricCard(title: "Est. update", value: "~" + est.formattedEstimate, icon: "timer")
            }
        }
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Editorial Review Card

    private func editorialPickCard(pick: BrewStoreEditorialPick) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .foregroundStyle(.yellow)
                Text("EDITOR'S CHOICE")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(pick.badge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
            }
            Text(pick.headline).font(.headline)
            Text(pick.review).font(.callout).foregroundStyle(.secondary).lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Collapsible Content Blocks

    private func versionSwitcherContent(siblings: [BrewStorePackage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch active symlinked version for this formula family:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(siblings) { sibling in
                    if sibling.id == currentPackage.id {
                        Button {} label: {
                            HStack(spacing: 6) {
                                Text(sibling.id).font(.caption.monospaced())
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(true)
                    } else {
                        Button {
                            manager.switchLinkedVersion(from: currentPackage, to: sibling)
                        } label: {
                            Text(sibling.id).font(.caption.monospaced())
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.isOperating)
                    }
                }
            }
        }
    }

    private var dependenciesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Required Components (\(currentPackage.dependencies.count))")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                if preferences.enableVisualDependencyGraph {
                    Button {
                        showingVisualGraph = true
                    } label: {
                        Label("Visual Graph", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .controlSize(.small)
                }

                if currentPackage.kind == .formula {
                    Button(showingDependencyTree ? "Hide Tree" : "Tree View") {
                        showingDependencyTree.toggle()
                        if showingDependencyTree, dependencyTree == nil {
                            Task { dependencyTree = await manager.fetchDependencyTree(for: currentPackage) }
                        }
                    }
                    .controlSize(.small)
                }
            }

            // Clickable Dependency Pills
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading, spacing: 8) {
                ForEach(currentPackage.dependencies, id: \.self) { depID in
                    let depPkg = manager.packages.first { $0.id == depID } ?? BrewStorePackage(
                        id: depID,
                        name: depID,
                        description: "",
                        homepage: "",
                        version: "",
                        kind: .formula
                    )
                    Button {
                        selectedDependencyPackage = depPkg
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: depPkg.kind == .cask ? "app.fill" : "terminal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(depPkg.isInstalled ? Color.green : Color.accentColor)

                            Text(depID)
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            if depPkg.isInstalled {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(depPkg.isInstalled ? "\(depID) (Installed) - Click to inspect" : "\(depID) (Available) - Click to inspect")
                }
            }

            if showingDependencyTree, let tree = dependencyTree {
                Text(tree)
                    .font(.caption.monospaced())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        }
    }

    private var dependentsContent: some View {
        Text(dependents.joined(separator: " · "))
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private var appStorageInspectorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown of disk space used by this app's binary, caches, and application data.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if storageInspector.isInspecting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Calculating disk breakdown…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let breakdown = storageInspector.breakdown {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("App Binary")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(breakdown.formattedBinary)
                            .font(.subheadline.bold())
                        Text(currentPackage.kind == .cask ? "Application bundle" : "Cellar binary")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Caches & Temp")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if breakdown.cacheBytes > 0 {
                                Text("Reclaimable")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(breakdown.formattedCache)
                            .font(.subheadline.bold())
                            .foregroundStyle(breakdown.cacheBytes > 0 ? .primary : .secondary)
                        Text("Safe to clear")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("App Data & State")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(breakdown.formattedData)
                            .font(.subheadline.bold())
                        Text("Keeps logins & prefs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }

                if let msg = storageInspector.statusMessage {
                    let isError = msg.lowercased().contains("failed") || msg.lowercased().contains("error")
                    HStack(spacing: 6) {
                        Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(isError ? Color.red : Color.green)
                            .font(.caption)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((isError ? Color.red : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }

                if !breakdown.cacheCandidates.isEmpty {
                    DisclosureGroup("Granular Cache Directories (\(breakdown.cacheCandidates.count))") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button("Select All") {
                                    storageInspector.selectAllCandidates()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)

                                Text("·")
                                    .foregroundStyle(.secondary)
                                    .font(.caption2)

                                Button("Deselect All") {
                                    storageInspector.deselectAllCandidates()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)

                                Spacer()

                                let selectedCount = breakdown.cacheCandidates.filter(\.isSelected).count
                                Text("\(selectedCount) of \(breakdown.cacheCandidates.count) selected")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)

                            ForEach(breakdown.cacheCandidates) { cand in
                                HStack(spacing: 8) {
                                    Button {
                                        storageInspector.toggleCandidateSelection(url: cand.url)
                                    } label: {
                                        Image(systemName: cand.isSelected ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(cand.isSelected ? Color.accentColor : Color.secondary)
                                    }
                                    .buttonStyle(.plain)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(cand.url.lastPathComponent)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        Text(cand.url.path)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(cand.formattedSize)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    storageInspector.toggleCandidateSelection(url: cand.url)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.bold())
                }

                HStack(spacing: 10) {
                    if breakdown.cacheBytes > 0 {
                        let selectedCandidates = breakdown.cacheCandidates.filter(\.isSelected)
                        if selectedCandidates.count < breakdown.cacheCandidates.count, !selectedCandidates.isEmpty {
                            Button {
                                storageInspector.cleanSelectedCaches(package: currentPackage)
                            } label: {
                                if storageInspector.isCleaning {
                                    ProgressView().controlSize(.small)
                                } else {
                                    let selectedTotal = selectedCandidates.reduce(0) { $0 + $1.size }
                                    let formattedSel = ByteCountFormatter.string(fromByteCount: selectedTotal, countStyle: .file)
                                    Label("Clean Selected (\(formattedSel))", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(storageInspector.isCleaning || manager.isOperating)
                        }

                        if selectedCandidates.count == breakdown.cacheCandidates.count {
                            Button {
                                storageInspector.cleanCaches(package: currentPackage)
                            } label: {
                                if storageInspector.isCleaning {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Clean All Caches (\(breakdown.formattedCache))", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(storageInspector.isCleaning || manager.isOperating)
                        } else {
                            Button {
                                storageInspector.cleanCaches(package: currentPackage)
                            } label: {
                                if storageInspector.isCleaning {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Clean All Caches (\(breakdown.formattedCache))", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(storageInspector.isCleaning || manager.isOperating)
                        }
                    }

                    if currentPackage.kind == .cask {
                        Button {
                            scanRemoval()
                        } label: {
                            if isScanningRemoval {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Deep Clean & Uninstall…", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isScanningRemoval || manager.isOperating)
                    }

                    Button {
                        storageInspector.inspect(package: currentPackage)
                    } label: {
                        Label("Re-scan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(storageInspector.isInspecting)
                }
            } else {
                Button {
                    storageInspector.inspect(package: currentPackage)
                } label: {
                    Label("Inspect App Storage & Caches", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let removalError {
                Text(removalError).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func caveatsContent(caveats: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MarkdownTextView(markdown: caveats, baseFont: .caption, lineSpacing: 3)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            let exportLines = shellAssistant.extractCaveatExports(from: caveats)
            if !exportLines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal.fill").foregroundStyle(.blue).font(.caption)
                        Text("Shell Environment Configuration Detected")
                            .font(.caption.bold())
                    }

                    Text(exportLines.joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Button {
                            let snippet = exportLines.joined(separator: "\n")
                            if shellAssistant.injectCaveatSnippet(packageName: currentPackage.name, snippet: snippet, manager: manager) {
                                caveatAppliedSuccess = true
                            }
                        } label: {
                            Label(
                                caveatAppliedSuccess ? "Applied to .\(shellAssistant.detectedShell)rc" : "1-Click Apply to .\(shellAssistant.detectedShell)rc",
                                systemImage: caveatAppliedSuccess ? "checkmark.circle.fill" : "arrow.down.doc.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(caveatAppliedSuccess ? .green : .blue)
                        .controlSize(.small)
                        .disabled(caveatAppliedSuccess)

                        if let status = shellAssistant.statusMessage {
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
            }
        }
    }

    private var securityInspectorContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if securityInspector.isInspecting {
                ProgressView("Inspecting binary signature & architecture…")
                    .controlSize(.small)
            } else if let report = securityInspector.report {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Binary Architecture").font(.caption2.bold()).foregroundStyle(.secondary)
                        Text(report.architecture.rawValue).font(.subheadline.bold())
                    }
                    Spacer()
                    Text(report.architecture == .appleSilicon || report.architecture == .universal2 ? "Apple Silicon Native" : "Rosetta 2")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (report.architecture == .appleSilicon || report.architecture == .universal2 ? Color.green : Color.orange).opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(report.architecture == .appleSilicon || report.architecture == .universal2 ? Color.green : Color.orange)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Code Signing Authority").font(.caption2.bold()).foregroundStyle(.secondary)
                        Text(report.codeSignAuthority).font(.caption.monospaced()).lineLimit(1)
                    }
                    Spacer()
                    if report.isHardenedRuntime {
                        Label("Hardened Runtime", systemImage: "lock.shield.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                if report.isQuarantined {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gatekeeper Quarantine Active").font(.caption.bold())
                            Text("macOS will prompt for approval before launching this app.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove Quarantine") {
                            securityInspector.removeQuarantine(package: currentPackage, manager: manager)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green).font(.caption)
                        Text("Clean Gatekeeper Status (No Quarantine)").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // Bottle Receipt & Checksum Integrity Auditor
                if currentPackage.kind == .formula {
                    let basePrefix = manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
                    let integrity = BrewStoreBottleIntegrityAuditor.auditPackage(package: currentPackage, prefix: basePrefix)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: integrity.status.icon)
                                .foregroundStyle(integrity.status == .verifiedBottle ? Color.green : Color.orange)
                            Text("Bottle Receipt & Checksum").font(.caption.bold())
                            Spacer()
                            Text(integrity.status.rawValue)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(integrity.status == .verifiedBottle ? Color.green.opacity(0.12) : Color.orange.opacity(0.12), in: Capsule())
                                .foregroundStyle(integrity.status == .verifiedBottle ? .green : .orange)
                        }

                        if let sha = integrity.bottleSHA256 {
                            HStack {
                                Text("Bottle SHA-256:").font(.caption2).foregroundStyle(.secondary)
                                Text(sha).font(.caption2.monospaced()).textSelection(.enabled)
                            }
                        }
                        if let compiler = integrity.compiler {
                            Text("Build compiler: \(compiler)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }

                // Package Version Pinning & Multi-Version Switcher
                if currentPackage.isInstalled {
                    let isPinned = pinningManager.isPinned(packageID: currentPackage.id)
                    let isPinning = pinningManager.isPinningInProgress(packageID: currentPackage.id)
                    let prefix = manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
                    let installedVersions = BrewStorePackagePinningManager.installedCellarVersions(for: currentPackage.id, prefix: prefix)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .foregroundStyle(isPinned ? Color.purple : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isPinned ? "Version Pinned" : "Version Pinning & Switcher").font(.caption.bold())
                                Text(isPinned ? "Locked at current version. `brew upgrade` will skip this package." : "Unlocked. Will automatically receive upgrades.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                pinningManager.togglePin(package: currentPackage, manager: manager)
                            } label: {
                                if isPinning {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.mini)
                                        Text(isPinned ? "Unpinning…" : "Pinning…")
                                    }
                                } else {
                                    Label(isPinned ? "Unpin Version" : "Pin Version", systemImage: isPinned ? "pin.slash.fill" : "pin.fill")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(manager.isOperating || isPinning)
                            .accessibilityIdentifier("PackageDetail.VersionPinButton")
                        }

                        if installedVersions.count > 1 {
                            Divider()
                            HStack {
                                Text("Switch Installed Version:").font(.caption2.bold()).foregroundStyle(.secondary)
                                Spacer()
                                Menu {
                                    ForEach(installedVersions, id: \.self) { ver in
                                        Button("Switch to v\(ver)") {
                                            BrewStorePackagePinningManager.shared.switchActiveVersion(packageID: currentPackage.id, version: ver, manager: manager)
                                        }
                                    }
                                } label: {
                                    Label("v\(currentPackage.version)", systemImage: "arrow.triangle.swap")
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                    // Ignore / Unignore Updates
                    let isIgnored = BrewStoreIgnoredUpdatesManager.shared.isIgnored(packageID: currentPackage.id)
                    HStack(spacing: 8) {
                        Image(systemName: isIgnored ? "bell.slash.fill" : "bell")
                            .foregroundStyle(isIgnored ? Color.purple : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update Notifications").font(.caption.bold())
                            Text(isIgnored ? "Updates are muted for this package." : "Updates are active and will notify you.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            BrewStoreIgnoredUpdatesManager.shared.toggleIgnore(packageID: currentPackage.id)
                        } label: {
                            Label(isIgnored ? "Unignore Updates" : "Ignore Updates", systemImage: isIgnored ? "bell" : "bell.slash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }

                // Known CVE Security Advisories
                let advisories = BrewStoreCVEScanningManager.advisories(for: currentPackage)
                if !advisories.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(advisories) { adv in
                            HStack(spacing: 8) {
                                Image(systemName: adv.severity.symbol)
                                    .foregroundStyle(adv.severity.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(adv.id).font(.caption.bold())
                                        Text(adv.severity.rawValue)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(adv.severity.color.opacity(0.15), in: Capsule())
                                            .foregroundStyle(adv.severity.color)
                                    }
                                    Text(adv.title).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let url = URL(string: adv.advisoryURL) {
                                    Button("Advisory") {
                                        NSWorkspace.shared.open(url)
                                    }
                                    .controlSize(.small)
                                }
                            }
                            .padding(8)
                            .background(adv.severity.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                if let status = securityInspector.statusMessage {
                    Text(status).font(.caption2.bold()).foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Analytics & Popularity

    private var analyticsDashboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Popularity & Install Activity", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                if let a = packageAnalytics {
                    let badge = a.momentumBadge
                    HStack(spacing: 4) {
                        Image(systemName: badge.symbol)
                        Text(badge.title)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(badge.isPositive ? Color.green : Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((badge.isPositive ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                }
            }

            if let a = packageAnalytics {
                HStack(spacing: 8) {
                    analyticsMetricPill(title: "7-Day (1 Wk)", value: a.formatted7d, icon: "flame.fill")
                    analyticsMetricPill(title: "30-Day (1 Mo)", value: a.formatted30d, icon: "calendar")
                    analyticsMetricPill(title: "90-Day (Quarter)", value: a.formatted90d, icon: "calendar.badge.clock")
                    analyticsMetricPill(title: "365-Day (1 Yr)", value: a.formatted365d, icon: "chart.line.uptrend.xyaxis")
                }

                // Direct vs Dependency Split Bar
                if a.installOnRequest30d != nil, a.install30d > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Direct Installs: \(Int(a.directRequestRatio * 100))%")
                                .font(.caption2.bold())
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Dependency Installs: \(Int((1.0 - a.directRequestRatio) * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor)
                                    .frame(width: max(geo.size.width * CGFloat(a.directRequestRatio) - 2, 0))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: max(geo.size.width * CGFloat(1.0 - a.directRequestRatio), 0))
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.top, 4)
                }
            } else if analyticsManager.isLoading["\(currentPackage.kind.rawValue):\(currentPackage.id)"] == true {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading install stats from Homebrew…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Install statistics aren't available for this package.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func analyticsMetricPill(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Similar & Alternative Tools Carousel

    @ViewBuilder
    private var similarToolsCarousel: some View {
        let alternatives = BrewStoreAlternativeRecommendationManager.findAlternatives(for: currentPackage, in: manager.packages)
        if !alternatives.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundStyle(Color.accentColor)
                    Text("Similar Tools & Alternatives").font(.title3.bold())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(alternatives) { alt in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Image(systemName: alt.kind == .cask ? "app.fill" : "terminal.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 34, height: 34)
                                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(alt.name)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(alt.displayKind)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text(alt.description.isEmpty ? "Alternative tool in the same category." : alt.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .frame(height: 32, alignment: .topLeading)

                                HStack {
                                    AppStoreActionButton(manager: manager, package: alt, size: .small)
                                    Spacer()
                                }
                            }
                            .padding(14)
                            .frame(width: 230)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - App Store Information Table

    private var informationTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Information").font(.title3.bold())

            VStack(spacing: 0) {
                infoRow(title: "Provider / Tap", value: currentPackage.tap ?? "homebrew/core")
                Divider()
                infoRow(title: "Kind", value: currentPackage.displayKind)
                Divider()
                if let cellar = currentPackage.cellarURL(prefix: manager.brewPrefix) {
                    infoRow(title: "Cellar Location", value: cellar.path)
                    Divider()
                }
                if let homepage = URL(string: currentPackage.homepage), !currentPackage.homepage.isEmpty {
                    HStack {
                        Text("Homepage").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Link(currentPackage.homepage, destination: homepage)
                            .font(.caption)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 14)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }
        .padding(.vertical, 8)
    }

    private func scanRemoval() {
        let names = currentPackage.applicationNames.isEmpty ? [currentPackage.name] : currentPackage.applicationNames
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        var appURL: URL?

        for name in names {
            let normalizedName = name.hasSuffix(".app") ? name : "\(name).app"
            let candidates = [
                URL(fileURLWithPath: "/Applications").appendingPathComponent(normalizedName),
                homeApplications.appendingPathComponent(normalizedName)
            ]
            if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                appURL = found
                break
            }
        }

        guard let targetURL = appURL ?? (names.first.map { URL(fileURLWithPath: "/Applications").appendingPathComponent($0.hasSuffix(".app") ? $0 : "\($0).app") }) else {
            removalError = "Homebrew did not report an application bundle for this cask."
            return
        }

        isScanningRemoval = true
        removalError = nil
        let bundleID = Bundle(url: targetURL)?.bundleIdentifier ?? ""
        let identity = BrewStoreAppIdentity(name: targetURL.deletingPathExtension().lastPathComponent, bundleIdentifier: bundleID, applicationURL: targetURL)
        Task.detached(priority: .userInitiated) {
            let plan = BrewStoreAppRemovalScanner().scan(application: identity)
            await MainActor.run {
                removalPlan = plan
                isScanningRemoval = false
                if plan.candidates.isEmpty {
                    removalError = "No leftover files found."
                } else {
                    showingRemoval = true
                }
            }
        }
    }
}

struct RemovalPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage
    let plan: BrewStoreRemovalPlan

    @State private var selectedCandidateIDs: Set<URL> = []
    @State private var isExecuting = false

    init(manager: HomebrewManager, package: BrewStorePackage, plan: BrewStoreRemovalPlan) {
        self.manager = manager
        self.package = package
        self.plan = plan
        _selectedCandidateIDs = State(initialValue: Set(plan.candidates.filter(\.isSelected).map(\.url)))
    }

    private var totalBytes: Int64 {
        plan.candidates.filter { selectedCandidateIDs.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean & Uninstall \(package.name)")
                        .font(.title2.bold())
                    Text("\(selectedCandidateIDs.count) residual items selected · \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }

            Divider()

            List(plan.candidates) { candidate in
                HStack(spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { selectedCandidateIDs.contains(candidate.url) },
                        set: { isSelected in
                            if isSelected {
                                selectedCandidateIDs.insert(candidate.url)
                            } else {
                                selectedCandidateIDs.remove(candidate.url)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.url.lastPathComponent).font(.body.bold())
                            Text(candidate.url.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(candidate.formattedSize)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                Button("Select All") {
                    selectedCandidateIDs = Set(plan.candidates.map(\.url))
                }
                Button("Deselect All") {
                    selectedCandidateIDs.removeAll()
                }
                Spacer()

                Button("Move Selected to Trash & Uninstall", role: .destructive) {
                    executeTrashAndUninstall()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExecuting || manager.isOperating)
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
    }

    private func executeTrashAndUninstall() {
        isExecuting = true
        let selected = plan.candidates.map { candidate in
            var updated = candidate
            updated.isSelected = selectedCandidateIDs.contains(candidate.url)
            return updated
        }
        let subPlan = BrewStoreRemovalPlan(id: plan.id, application: plan.application, createdAt: plan.createdAt, candidates: selected)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
            home.appendingPathComponent("Library/Application Support"),
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Containers"),
            home.appendingPathComponent("Library/Group Containers"),
            home.appendingPathComponent("Library/Preferences"),
            home.appendingPathComponent("Library/Logs")
        ]
        let executor = BrewStoreTrashExecutor(validator: BrewStorePathSafetyValidator(allowedRoots: roots))
        _ = executor.execute(plan: subPlan)
        isExecuting = false
        dismiss()
        DispatchQueue.main.async {
            BrewStoreUninstallCoordinator.shared.requestUninstall(package: package, manager: manager)
        }
    }
}
