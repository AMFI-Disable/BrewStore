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
    @State private var removalStatusMessage: String?
    @State private var removalStatusIsSuccess = false
    @State private var dependencyTree: String?
    @State private var showingDependencyTree = false

    @State private var activeSheet: PackageDetailSheet?
    @State private var caskQuarantineItem: CaskQuarantineItem?

    @StateObject private var securityInspector = BrewStoreSecurityInspector()
    @ObservedObject private var entitlementsAuditor = CaskEntitlementsAuditor.shared
    @StateObject private var storageInspector = BrewStoreAppStorageInspector()
    @ObservedObject private var analyticsManager = BrewStoreAnalyticsManager.shared
    @ObservedObject private var pinningManager = BrewStorePackagePinningManager.shared
    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared
    @ObservedObject private var auditor = OrphanAndKegAuditor.shared
    @Environment(\.dismiss) private var dismiss
    var onDismiss: (() -> Void)?
    @State private var packageAnalytics: PackageInstallAnalytics?
    @State private var selectedDependencyPackage: BrewStorePackage?
    @State private var copiedExportsToast = false
    @State private var showingPruneOrphanConfirm = false
    @State private var showingToggleKegConfirm = false

    private var effectivePrefix: String {
        manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
    }

    private var matchingKegOnlyItem: KegOnlyPackageItem? {
        guard currentPackage.kind == .formula, currentPackage.isInstalled else { return nil }
        return auditor.report?.kegOnlyPackages.first {
            $0.id.lowercased() == currentPackage.id.lowercased() || $0.name.lowercased() == currentPackage.name.lowercased()
        }
    }

    private var matchingOrphanItem: LeafPackageItem? {
        guard currentPackage.kind == .formula, currentPackage.isInstalled else { return nil }
        return auditor.report?.orphans.first {
            $0.id.lowercased() == currentPackage.id.lowercased() || $0.name.lowercased() == currentPackage.name.lowercased()
        }
    }

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

    private var familyVariants: [BrewStorePackage] {
        manager.fetchFamilyVariants(for: currentPackage)
    }

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 680

            VStack(spacing: 0) {
                PackageDetailHeaderView(
                    package: currentPackage,
                    manager: manager,
                    installedAppIcon: installedAppIcon,
                    matchingKegOnlyItem: matchingKegOnlyItem,
                    matchingOrphanItem: matchingOrphanItem,
                    onDismiss: { handleDismiss() },
                    activeSheet: $activeSheet
                )
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
                if currentPackage.kind == .cask {
                    await entitlementsAuditor.audit(package: currentPackage)
                    caskQuarantineItem = await BrewStoreCaskQuarantineAuditor.shared.auditPackage(package: currentPackage, prefix: effectivePrefix)
                }
            }
            if currentPackage.kind == .formula, currentPackage.isInstalled {
                isLoadingDependents = true
                dependents = await manager.fetchDependents(for: currentPackage)
                isLoadingDependents = false
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .removal(let plan):
                RemovalPreviewView(manager: manager, package: currentPackage, plan: plan)
            case .visualGraph:
                DependencyGraphView(manager: manager, rootPackage: currentPackage)
            case .advancedInstall:
                AdvancedInstallView(manager: manager, package: currentPackage)
            case .securityApproval:
                let requiredPerms = TCCPermissionManager.shared.detectPermissions(for: currentPackage)
                SecurityApprovalSheet(package: currentPackage, permissions: requiredPerms)
            case .versionSwitcher:
                VersionLinkView(manager: manager)
            case .upgradeDiff:
                UpgradeDiffViewSheet(package: currentPackage, manager: manager)
            case .bottleIntegrity:
                BottleIntegrityAuditorView(manager: manager)
            case .caskQuarantine:
                CaskQuarantineAuditorView(manager: manager)
            case .sourceBuildStudio:
                SourceBuildStudioView(manager: manager, targetPackage: currentPackage)
            case .blastRadius:
                RemovalBlastRadiusSimulatorView(
                    package: currentPackage,
                    manager: manager,
                    onDismiss: { activeSheet = nil },
                    onProceedUninstall: currentPackage.isInstalled ? {
                        BrewStoreUninstallCoordinator.shared.requestUninstall(package: currentPackage, manager: manager)
                    } : nil
                )
            case .showdown(let altPkg):
                BrewStorePackageShowdownSheet(
                    packageA: currentPackage,
                    packageB: altPkg,
                    manager: manager
                )
            }
        }
        .detailModalOverlay(item: $selectedDependencyPackage) { depPkg in
            PackageDetailView(manager: manager, package: depPkg, onDismiss: {
                selectedDependencyPackage = nil
            })
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
            PackageDetailCaveatsCard(package: currentPackage, manager: manager, caveats: caveats)
        }

        if !currentPackage.dependencies.isEmpty || !dependents.isEmpty {
            dependenciesSection
        }

        if familyVariants.count > 1 {
            versionSwitcherSection(variants: familyVariants)
        }

        if currentPackage.kind == .formula, currentPackage.isInstalled {
            KegSnapshotCardView(manager: manager, packageID: currentPackage.id)

            if let keg = matchingKegOnlyItem {
                kegGovernanceCard(keg: keg)
            }

            if let orphan = matchingOrphanItem {
                orphanPruneCard(orphan: orphan)
            }

            let integrity = BrewStoreBottleIntegrityAuditor.auditPackage(package: currentPackage, prefix: effectivePrefix)
            if integrity.hasIntegrityIssue {
                integrityWarningCard(integrity: integrity)
            }

            if let quarantine = caskQuarantineItem, quarantine.isQuarantined {
                caskQuarantineWarningCard(item: quarantine)
            }
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

    private var inspectorColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            PackageDetailSpecificationsCard(package: currentPackage, packageAnalytics: packageAnalytics)

            PackageDetailInformationCard(package: currentPackage, brewPrefix: manager.brewPrefix)

            PackageDetailSecurityCard(
                package: currentPackage,
                manager: manager,
                effectivePrefix: effectivePrefix,
                securityInspector: securityInspector,
                entitlementsAuditor: entitlementsAuditor,
                caskQuarantineItem: caskQuarantineItem,
                activeSheet: $activeSheet
            )

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
        HumanizedErrorBanner(
            rawError: error,
            manager: manager,
            package: currentPackage,
            onDismiss: {
                manager.clearErrorMessage()
            }
        )
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
                        activeSheet = .visualGraph
                    } label: {
                        Label("Visual Graph", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .controlSize(.small)
                }

                if currentPackage.isInstalled {
                    Button {
                        activeSheet = .blastRadius
                    } label: {
                        Label("Impact Simulator", systemImage: "waveform.path.ecg")
                    }
                    .controlSize(.small)
                    .help("Simulate pre-removal blast radius on reverse dependencies and active daemons")
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

            if showingDependencyTree {
                DependencyNodeTreeView(
                    rootPackage: currentPackage,
                    allPackages: manager.packages,
                    asciiTree: dependencyTree,
                    onSelectPackage: { selectedPkg in
                        selectedDependencyPackage = selectedPkg
                    }
                )
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

    private func versionSwitcherSection(variants: [BrewStorePackage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Version Family (\(variants.count) Versions)", systemImage: "arrow.triangle.swap")
                    .font(.headline)
                Spacer()
                Button("Full Switcher Hub…") {
                    activeSheet = .versionSwitcher
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            versionSwitcherContent(variants: variants)
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
                activeSheet = .securityApproval
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

    private func versionSwitcherContent(variants: [BrewStorePackage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch active symlink or install alternative releases for this runtime family:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(variants) { variant in
                        HStack(spacing: 6) {
                            Text(variant.id).font(.caption.monospaced())
                            if variant.id == currentPackage.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if variant.isInstalled {
                                Button("Switch") {
                                    manager.switchLinkedVersion(from: currentPackage, to: variant)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                                .disabled(manager.isOperating)
                            } else {
                                Button("Install") {
                                    manager.perform(package: variant, action: .install)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .disabled(manager.isOperating)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 2)
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

            if let removalStatusMessage {
                HStack(spacing: 6) {
                    Image(systemName: removalStatusIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(removalStatusIsSuccess ? Color.green : Color.orange)
                    Text(removalStatusMessage)
                        .font(.caption)
                        .foregroundStyle(removalStatusIsSuccess ? Color.primary : Color.orange)
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

                    Text("\(alternatives.count)")
                        .font(.caption2.bold().monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)

                    Spacer()

                    if let firstAlt = alternatives.first {
                        Button {
                            activeSheet = .showdown(firstAlt)
                        } label: {
                            Label("Compare in Showdown", systemImage: "flame.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .controlSize(.small)
                        .help("Launch head-to-head comparison showdown between \(currentPackage.name) and \(firstAlt.name)")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(alternatives) { alt in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    selectedDependencyPackage = alt
                                } label: {
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
                                                    .foregroundStyle(.primary)
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
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .buttonStyle(.plain)

                                HStack {
                                    AppStoreActionButton(manager: manager, package: alt, size: .small)
                                    Spacer()
                                    Button {
                                        activeSheet = .showdown(alt)
                                    } label: {
                                        Image(systemName: "flame.fill")
                                            .font(.caption2)
                                            .foregroundStyle(Color.orange)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .background(Color.orange.opacity(0.12), in: Circle())
                                    .help("Compare \(currentPackage.name) vs \(alt.name) in Showdown")
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
            removalStatusMessage = "Homebrew did not report an application bundle for this cask."
            removalStatusIsSuccess = false
            return
        }

        isScanningRemoval = true
        removalStatusMessage = nil
        let bundleID = Bundle(url: targetURL)?.bundleIdentifier ?? ""
        let identity = BrewStoreAppIdentity(name: targetURL.deletingPathExtension().lastPathComponent, bundleIdentifier: bundleID, applicationURL: targetURL)
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                BrewStoreAppRemovalScanner().scan(application: identity)
            }.value

            guard !Task.isCancelled else { return }
            removalPlan = plan
            isScanningRemoval = false
            if plan.candidates.isEmpty {
                removalStatusMessage = "Your Mac is clean — no leftover files or caches were found for this app."
                removalStatusIsSuccess = true
            } else {
                activeSheet = .removal(plan)
            }
        }
    }

    // MARK: - Keg-Only & Orphan Leaf Governance

    @ViewBuilder
    private func kegGovernanceCard(keg: KegOnlyPackageItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: keg.isForceLinked ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                        .foregroundStyle(keg.isForceLinked ? .orange : .blue)
                    Text("Keg-Only PATH & Compiler Governance")
                        .font(.headline)
                }

                Spacer()

                Button {
                    showingToggleKegConfirm = true
                } label: {
                    Text(keg.isForceLinked ? "Unlink (Restore Isolation)" : "Force Link Binary")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(auditor.operatingPackageID != nil)
            }

            Text(keg.humanReadableReason)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Environment Exports")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        auditor.copyToClipboard(keg.fullShellSnippet)
                        copiedExportsToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedExportsToast = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedExportsToast ? "checkmark" : "doc.on.doc")
                            Text(copiedExportsToast ? "Copied!" : "Copy Shell Exports")
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                }

                Text(keg.fullShellSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
        .confirmationDialog(
            keg.isForceLinked ? "Unlink \(keg.name)?" : "Force Link \(keg.name)?",
            isPresented: $showingToggleKegConfirm,
            titleVisibility: .visible
        ) {
            Button(keg.isForceLinked ? "Unlink (brew unlink)" : "Force Link (brew link --overwrite --force)", role: keg.isForceLinked ? .none : .destructive) {
                Task {
                    _ = await auditor.toggleKegLink(packageID: keg.id, forceLink: !keg.isForceLinked, prefix: effectivePrefix, manager: manager)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if keg.isForceLinked {
                Text("This will remove symlinks from \(effectivePrefix)/bin, restoring safe isolated status.")
            } else {
                Text("Warning: Force linking a keg-only package symlinks its binaries directly into \(effectivePrefix)/bin, which may override macOS system binaries or other tools.")
            }
        }
    }

    @ViewBuilder
    private func orphanPruneCard(orphan: LeafPackageItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Orphan Dependency Leaf")
                        .font(.headline)
                    Text("(\(orphan.formattedSize))")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }

                Text("This package was installed as a dependency for software that has since been uninstalled. It is currently not required by any installed formula.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                showingPruneOrphanConfirm = true
            } label: {
                Label("Prune (\(orphan.formattedSize))", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(auditor.operatingPackageID != nil)
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
        .confirmationDialog(
            "Prune \(orphan.name)?",
            isPresented: $showingPruneOrphanConfirm,
            titleVisibility: .visible
        ) {
            Button("Prune Dependency", role: .destructive) {
                Task {
                    _ = await auditor.pruneSingleOrphan(packageID: orphan.id, prefix: effectivePrefix, manager: manager)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will run 'brew uninstall \(orphan.id)' to free up \(orphan.formattedSize) from your Cellar.")
        }
    }

    // MARK: - Bottle Integrity Helpers

    private func integrityStatusColor(_ status: BottleIntegrityStatus) -> Color {
        switch status {
        case .verifiedBottle: return .green
        case .builtFromSource: return .purple
        case .unmanagedOrManual: return .orange
        case .corruptedOrTampered: return .red
        }
    }

    private func integrityStatusLabel(_ status: BottleIntegrityStatus) -> String {
        switch status {
        case .verifiedBottle: return "Verified"
        case .builtFromSource: return "Source"
        case .unmanagedOrManual: return "Unmanaged"
        case .corruptedOrTampered: return "Corrupted"
        }
    }

    @ViewBuilder
    private func integrityWarningCard(integrity: BottleIntegrityReport) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Bottle Integrity Alert")
                        .font(.headline)
                    Text("(\(integrityStatusLabel(integrity.status)))")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }

                Text(integrity.failureReason ?? "Cellar binaries or receipts appear corrupted or altered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                Task {
                    _ = await BrewStoreBottleIntegrityAuditor.shared.reinstallBottle(packageID: currentPackage.id, prefix: effectivePrefix, manager: manager)
                }
            } label: {
                Label("Reinstall Clean Bottle", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func caskQuarantineWarningCard(item: CaskQuarantineItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Gatekeeper Quarantine Active")
                        .font(.headline)
                    Text("(Quarantined)")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }

                Text("This application bundle has extended quarantine attributes that may trigger Gatekeeper launch blocks or verification dialogs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    let res = await BrewStoreCaskQuarantineAuditor.shared.removeQuarantine(for: item)
                    if case .success = res {
                        caskQuarantineItem = await BrewStoreCaskQuarantineAuditor.shared.auditPackage(package: currentPackage, prefix: effectivePrefix)
                    }
                }
            } label: {
                Label("Clear Quarantine", systemImage: "checkmark.shield")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button {
                activeSheet = .caskQuarantine
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Audit Details")
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
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
