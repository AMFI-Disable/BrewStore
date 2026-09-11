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

    @State private var showingAdvancedInstallSheet = false
    @State private var showingSecurityApprovalSheet = false

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
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 680

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)

                Divider()

                if isWide {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                mainContentColumn
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.md)
                        }
                        .frame(maxWidth: .infinity)

                        Divider()

                        ScrollView {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                inspectorColumn
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.md)
                        }
                        .frame(width: 260)
                        .background(Color.secondary.opacity(0.02))
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            mainContentColumn
                            Divider()
                                .padding(.vertical, Spacing.xs)
                            inspectorColumn
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                    }
                }
            }
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
        .sheet(isPresented: $showingSecurityApprovalSheet) {
            let requiredPerms = TCCPermissionManager.shared.detectPermissions(for: currentPackage)
            SecurityApprovalSheet(package: currentPackage, permissions: requiredPerms)
        }
        .detailModalOverlay(item: $selectedDependencyPackage) { depPkg in
            PackageDetailView(manager: manager, package: depPkg, onDismiss: {
                selectedDependencyPackage = nil
            })
        }
    }

    // MARK: - App Store Pinned Header View

    @ViewBuilder
    private var headerView: some View {
        let isWishlisted = wishlistManager.isWishlisted(id: currentPackage.id)

        VStack(alignment: .leading, spacing: Spacing.sm) {
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

            // Identity & Primary Actions Row
            HStack(alignment: .center, spacing: Spacing.md) {
                if let icon = installedAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                } else {
                    Image(systemName: currentPackage.kind == .cask ? "app.fill" : "terminal.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.tint)
                        .frame(width: 48, height: 48)
                        .background(
                            Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(currentPackage.name)
                            .font(.title2.bold())
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if currentPackage.isInstalled, pinningManager.isPinned(packageID: currentPackage.id) {
                            HStack(spacing: 3) {
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
                            HStack(spacing: 3) {
                                Image(systemName: badge.icon)
                                Text(badge.title)
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }

                        if currentPackage.isOutdated {
                            let est = BrewStoreUpdateEstimator.estimate(for: currentPackage)
                            HStack(spacing: 3) {
                                Image(systemName: "timer").font(.caption2)
                                Text("~\(est.formattedEstimate)")
                                    .font(.caption2.bold().monospaced())
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text(currentPackage.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        Text("•").font(.caption2).foregroundStyle(.secondary)
                        Text("v\(currentPackage.version)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("•").font(.caption2).foregroundStyle(.secondary)
                        Text(currentPackage.displayKind).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Action Buttons Bar
                HStack(spacing: 6) {
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
                                HStack(spacing: 4) {
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
                }
            }
        }
    }

    // MARK: - Main Content Column

    @ViewBuilder
    private var mainContentColumn: some View {
        if isOperatingThisPackage {
            operationDrawer
        }

        if let pick = BrewStoreEditorialPick.pick(for: currentPackage.id) {
            editorialPickCard(pick: pick)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("About").font(.headline)
            if !currentPackage.description.isEmpty {
                Text(currentPackage.description)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            } else {
                Text("No description provided for this package.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)

        if let caveats = currentPackage.caveats, !caveats.isEmpty {
            caveatsSection(caveats: caveats)
        }

        if !currentPackage.dependencies.isEmpty || !dependents.isEmpty {
            dependenciesSection
        }

        if siblings.count > 1 {
            versionSwitcherSection(siblings: siblings)
        }

        if preferences.enableAppCleaner, currentPackage.isInstalled {
            storageSection
        }

        similarToolsCarousel

        analyticsDashboardSection

        if !manager.statusMessage.isEmpty {
            Text(manager.statusMessage).font(.callout).foregroundStyle(.secondary)
        }
        if let error = manager.errorMessage {
            errorBanner(error: error)
        }

        Color.clear
            .frame(minHeight: 30)
            .contentShape(Rectangle())
            .onTapGesture {
                handleDismiss()
            }
    }

    // MARK: - Inspector Column

    @ViewBuilder
    private var inspectorColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            specificationsCard

            informationCard

            securityInspectorCard

            if currentPackage.isInstalled {
                packageControlsCard
            }

            let requiredPerms = TCCPermissionManager.shared.detectPermissions(for: currentPackage)
            if !requiredPerms.isEmpty {
                systemPermissionsCard(requiredPerms: requiredPerms)
            }

            Color.clear
                .frame(minHeight: 30)
                .contentShape(Rectangle())
                .onTapGesture {
                    handleDismiss()
                }
        }
    }

    // MARK: - Main Column Helper Subviews

    private var operationDrawer: some View {
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

    private func errorBanner(error: String) -> some View {
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

    private func caveatsSection(caveats: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill").foregroundStyle(.blue).font(.caption)
                Text("Configuration & Shell Setup").font(.headline)
            }

            MarkdownTextView(markdown: caveats, baseFont: .caption, lineSpacing: 3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.sm))

            let exportLines = shellAssistant.extractCaveatExports(from: caveats)
            if !exportLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exportLines.joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Button {
                            let snippet = exportLines.joined(separator: "\n")
                            if shellAssistant.injectCaveatSnippet(
                                packageName: currentPackage.name,
                                snippet: snippet,
                                manager: manager
                            ) {
                                caveatAppliedSuccess = true
                            }
                        } label: {
                            Label(
                                caveatAppliedSuccess ?
                                    "Applied to .\(shellAssistant.detectedShell)rc" :
                                    "1-Click Apply to .\(shellAssistant.detectedShell)rc",
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
                .padding(8)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Color.blue.opacity(0.2), lineWidth: 1))
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(
                    "Dependencies (\(currentPackage.dependencies.count))",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .font(.headline)

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

            if !currentPackage.dependencies.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 6) {
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
                            HStack(spacing: 5) {
                                Image(systemName: depPkg.kind == .cask ? "app.fill" : "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(depPkg.isInstalled ? Color.green : Color.accentColor)

                                Text(depID)
                                    .font(.caption.monospaced().bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 2)

                                if depPkg.isInstalled {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help(
                            depPkg.isInstalled ?
                                "\(depID) (Installed) - Click to inspect" :
                                "\(depID) (Available) - Click to inspect"
                        )
                    }
                }
            }

            if showingDependencyTree, let tree = dependencyTree {
                Text(tree)
                    .font(.caption.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }

            if !dependents.isEmpty {
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Used By (\(dependents.count) Packages)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(dependents.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private func versionSwitcherSection(siblings: [BrewStorePackage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Installed Family Versions (\(siblings.count))", systemImage: "arrow.triangle.swap")
                .font(.headline)
            versionSwitcherContent(siblings: siblings)
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storage & Cache Breakdown", systemImage: "internaldrive.fill")
                .font(.headline)
            appStorageInspectorContent
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    // MARK: - Inspector Column Helper Subviews

    private var specificationsCard: some View {
        let footprint = BrewStoreBottleFootprintEstimator.estimateFootprint(for: currentPackage)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Specifications").font(.headline)

            VStack(spacing: 6) {
                specRow(
                    title: "Type",
                    value: currentPackage.kind == .cask ? "macOS App" : "CLI Binary",
                    icon: currentPackage.kind == .cask ? "app.fill" : "terminal.fill"
                )
                Divider()
                specRow(
                    title: "Status",
                    value: currentPackage.isInstalled ?
                        (currentPackage.isOutdated ? "Update" : "Installed") :
                        "Available",
                    icon: currentPackage.isInstalled ? "checkmark.circle.fill" : "circle"
                )
                Divider()
                specRow(title: "Download", value: "~" + footprint.formattedDownloadSize, icon: "arrow.down.circle")
                Divider()
                specRow(title: "Disk Space", value: "~" + footprint.formattedFootprintSize, icon: "internaldrive")
                Divider()
                specRow(title: "30d Installs", value: packageAnalytics?.formatted30d ?? "—", icon: "calendar")
                if currentPackage.isOutdated {
                    let est = BrewStoreUpdateEstimator.estimate(for: currentPackage)
                    Divider()
                    specRow(title: "Est. Update", value: "~" + est.formattedEstimate, icon: "timer")
                }
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private func specRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tint)
                .frame(width: 14)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
        }
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Information").font(.headline)

            VStack(spacing: 6) {
                HStack {
                    Text("Tap / Source").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(currentPackage.tap ?? "homebrew/core").font(.caption.monospaced()).lineLimit(1)
                }
                Divider()
                HStack {
                    Text("Kind").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(currentPackage.displayKind).font(.caption)
                }
                if let cellar = currentPackage.cellarURL(prefix: manager.brewPrefix) {
                    Divider()
                    HStack {
                        Text("Cellar").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(cellar.lastPathComponent).font(.caption.monospaced()).lineLimit(1)
                    }
                    .help(cellar.path)
                }
                if let homepage = URL(string: currentPackage.homepage), !currentPackage.homepage.isEmpty {
                    Divider()
                    HStack {
                        Text("Homepage").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Link(destination: homepage) {
                            HStack(spacing: 3) {
                                Text("Visit Site")
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private var securityInspectorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Security & Integrity").font(.headline)

            if securityInspector.isInspecting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Inspecting binary…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let report = securityInspector.report {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Architecture").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        let isSilicon = report.architecture == .appleSilicon || report.architecture == .universal2
                        Text(isSilicon ? "Apple Silicon" : "Rosetta 2")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (isSilicon ? Color.green : Color.orange).opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(isSilicon ? Color.green : Color.orange)
                    }

                    Divider()

                    HStack {
                        Text("Signing").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(report.codeSignAuthority).font(.caption.monospaced()).lineLimit(1)
                    }

                    if report.isHardenedRuntime {
                        Divider()
                        HStack {
                            Text("Runtime").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Label("Hardened", systemImage: "lock.shield.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                        }
                    }

                    Divider()

                    if report.isQuarantined {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Quarantine Active", systemImage: "exclamationmark.shield.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button("Remove") {
                                    securityInspector.removeQuarantine(package: currentPackage, manager: manager)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            Text("macOS will prompt for approval before launch.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green).font(.caption2)
                            Text("Clean Gatekeeper").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "shield").foregroundStyle(.secondary).font(.caption2)
                    Text("Standard Security").font(.caption).foregroundStyle(.secondary)
                }
            }

            if currentPackage.kind == .formula {
                Divider()
                let prefix = manager.brewPrefix ??
                    (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
                let integrity = BrewStoreBottleIntegrityAuditor.auditPackage(package: currentPackage, prefix: prefix)
                HStack {
                    Image(systemName: integrity.status.icon)
                        .font(.caption2)
                        .foregroundStyle(integrity.status == .verifiedBottle ? Color.green : Color.orange)
                    Text("Bottle Integrity").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(integrity.status == .verifiedBottle ? "Verified" : "Source")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (integrity.status == .verifiedBottle ? Color.green : Color.orange).opacity(0.12),
                            in: Capsule()
                        )
                        .foregroundStyle(integrity.status == .verifiedBottle ? .green : .orange)
                }
            }

            let advisories = BrewStoreCVEScanningManager.advisories(for: currentPackage)
            if !advisories.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(advisories) { adv in
                        HStack(spacing: 4) {
                            Image(systemName: adv.severity.symbol)
                                .font(.caption2)
                                .foregroundStyle(adv.severity.color)
                            Text(adv.id).font(.caption2.bold())
                            Spacer()
                            if let url = URL(string: adv.advisoryURL) {
                                Link("Advisory", destination: url)
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private var packageControlsCard: some View {
        let isPinned = pinningManager.isPinned(packageID: currentPackage.id)
        let isPinning = pinningManager.isPinningInProgress(packageID: currentPackage.id)
        let prefix = manager.brewPrefix ??
            (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let installedVersions = BrewStorePackagePinningManager.installedCellarVersions(
            for: currentPackage.id,
            prefix: prefix
        )
        let isIgnored = BrewStoreIgnoredUpdatesManager.shared.isIgnored(packageID: currentPackage.id)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Version Controls").font(.headline)

            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isPinned ? "Version Pinned" : "Version Pinning")
                            .font(.caption.bold())
                        Text(isPinned ? "Upgrades locked" : "Receives updates")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        pinningManager.togglePin(package: currentPackage, manager: manager)
                    } label: {
                        if isPinning {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(isPinned ? "Unpin" : "Pin")
                                .font(.caption2.bold())
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(manager.isOperating || isPinning)
                    .accessibilityIdentifier("PackageDetail.VersionPinButton")
                }

                if installedVersions.count > 1 {
                    Divider()
                    HStack {
                        Text("Active Version").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(installedVersions, id: \.self) { ver in
                                Button("v\(ver)") {
                                    BrewStorePackagePinningManager.shared.switchActiveVersion(
                                        packageID: currentPackage.id,
                                        version: ver,
                                        manager: manager
                                    )
                                }
                            }
                        } label: {
                            Text("v\(currentPackage.version)")
                                .font(.caption.monospaced())
                        }
                        .controlSize(.mini)
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications").font(.caption.bold())
                        Text(isIgnored ? "Updates muted" : "Updates notified")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        BrewStoreIgnoredUpdatesManager.shared.toggleIgnore(packageID: currentPackage.id)
                    } label: {
                        Text(isIgnored ? "Unmute" : "Mute")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private func systemPermissionsCard(requiredPerms: [TCCPermissionKind]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(requiredPerms.count) System Permission(s)", systemImage: "hand.raised.square.on.square.fill")
                .font(.caption.bold())
                .foregroundStyle(.blue)
            Button("Review Approvals") {
                showingSecurityApprovalSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.sm))
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
