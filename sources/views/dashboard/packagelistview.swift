import AppKit
import SwiftUI

struct PackageListView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject private var pinningManager = BrewStorePackagePinningManager.shared
    let kind: BrewPackageKind?
    let title: String
    var updatesOnly = false
    var installedOnly = false
    var showHeader = true
    @State private var search = ""
    @State private var selectedKindFilter: BrewPackageKind?
    @State private var selectedTap = "All Taps"
    @State private var showPinnedOnly = false
    @State private var isSelectionMode = false
    @State private var selectedPackageIDs: Set<String> = []
    @State private var showingMASSheet = false
    @State private var selectedPackageForDetail: BrewStorePackage?
    @State private var quickLookPackage: BrewStorePackage?

    @State private var licenseFilter: PackageLicenseFilter = .all
    @State private var editorialFilter: PackageEditorialFilter = .all
    @State private var sortOption: PackageSortOption = .nameAsc
    @State private var groupingOption: PackageGroupingOption = .none

    private var basePackages: [BrewStorePackage] {
        if installedOnly {
            return manager.packages.filter(\.isInstalled)
        }
        return manager.packages
    }

    private var availableTaps: [String] {
        let taps = Array(Set(basePackages.compactMap(\.tap))).sorted()
        return ["All Taps"] + taps
    }

    private var packages: [BrewStorePackage] {
        BrewStorePackageFilterEngine.filterAndSort(
            packages: basePackages,
            query: search,
            kind: kind ?? selectedKindFilter,
            tap: selectedTap,
            pinnedOnly: showPinnedOnly,
            updatesOnly: updatesOnly,
            license: licenseFilter,
            editorial: editorialFilter,
            sort: sortOption,
            pinnedIDs: pinningManager.pinnedPackageIDs
        )
    }

    private var groupedSections: [(title: String, packages: [BrewStorePackage])] {
        BrewStorePackageFilterEngine.groupPackages(packages, by: groupingOption)
    }

    private var installedCount: Int {
        basePackages.filter(\.isInstalled).count
    }

    private var selectedPackages: [BrewStorePackage] {
        packages.filter { selectedPackageIDs.contains($0.id) }
    }

    private var hasActiveFilters: Bool {
        licenseFilter != .all || editorialFilter != .all || groupingOption != .none || sortOption != .nameAsc
    }

    private var activeFilterCount: Int {
        var count = 0
        if licenseFilter != .all {
            count += 1
        }
        if editorialFilter != .all {
            count += 1
        }
        if groupingOption != .none {
            count += 1
        }
        if sortOption != .nameAsc {
            count += 1
        }
        return count
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(title)
                            .font(.title2.bold())
                            .lineLimit(1)
                        if updatesOnly, packages.isEmpty {
                            if manager.errorMessage != nil {
                                Text("Update status unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            } else {
                                Text("All \(installedCount) packages are up to date")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else if updatesOnly {
                            Text("\(packages.count) update\(packages.count == 1 ? "" : "s") available · \(installedCount) installed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("\(packages.count) packages · \(installedCount) installed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: Spacing.md)

                    HStack(spacing: Spacing.sm) {
                        if updatesOnly {
                            Button {
                                showingMASSheet = true
                            } label: {
                                Label("Mac App Store", systemImage: "apple.logo")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !packages.isEmpty {
                            Button(isSelectionMode ? "Done" : "Select") {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedPackageIDs.removeAll()
                                }
                            }
                            .controlSize(.small)
                        }

                        Button(action: manager.refresh) {
                            if manager.isBackgroundSyncing {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("Syncing…")
                                }
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .controlSize(.small)
                        .disabled(manager.isLoading || manager.isOperating)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xs)
            } else if updatesOnly || !packages.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Text("\(packages.count) packages · \(installedCount) installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if manager.isBackgroundSyncing {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Syncing…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if updatesOnly {
                        Button {
                            showingMASSheet = true
                        } label: {
                            Label("Mac App Store", systemImage: "apple.logo")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !packages.isEmpty {
                        Button(isSelectionMode ? "Done" : "Select") {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedPackageIDs.removeAll()
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)
            }

            if installedOnly {
                AppleSiliconRosettaBannerView(manager: manager)
            }

            if updatesOnly, !packages.isEmpty {
                let updateEstimate = BrewStoreUpdateEstimator.estimate(for: packages)

                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                            .rotationEffect(.degrees(manager.isOperating ? 360 : 0))
                            .animation(manager.isOperating ? .linear(duration: 1.2).repeatForever(autoreverses: false) : .default, value: manager.isOperating)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("\(packages.count) Pending Update\(packages.count == 1 ? "" : "s")")
                                .font(.headline)

                            if let live = BrewStoreUpdateEstimator.liveRemainingTimeString(manager: manager) {
                                Text(live)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            } else if manager.isLoading {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("Calculating Estimates…")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(.secondary)
                            } else {
                                HStack(spacing: 5) {
                                    Text("Provisional Est. ~\(updateEstimate.formattedEstimate)")
                                        .font(.caption.bold())
                                    if BrewStoreSpeedTestManager.shared.isRunningTest {
                                        ProgressView().controlSize(.mini)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                                .foregroundStyle(.orange)
                                .help("Provisional estimate dynamically updates as live bandwidth measurements change.")
                            }

                            if let speedMBps = BrewStoreSpeedTestManager.cachedDownloadSpeedMBps {
                                Text(String(format: "Live bandwidth: %.1f MB/s", speedMBps))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("\(updateEstimate.detailedSummary) · Estimates are provisional and dynamically adapt to network conditions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        BrewStoreActionReviewCoordinator.shared.requestUpgrade(packages: packages, manager: manager) {
                            manager.upgradeAllPackages()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if manager.isOperating {
                                ProgressView().controlSize(.small)
                                Text(BrewStoreUpdateEstimator.liveRemainingTimeString(manager: manager) ?? "Upgrading…")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                Text(manager.isLoading ? "Upgrade All" : "Upgrade All · ~\(updateEstimate.formattedEstimate)")
                            }
                        }
                        .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.orange)
                    .controlSize(.regular)
                    .disabled(manager.isOperating)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1.5)
                )
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            // Filter & Organization Control Bar with In-Section Search
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    BrewStoreSectionSearchBar(text: $search, placeholder: "Search \(title.lowercased()) packages…", count: packages.count)
                        .frame(minWidth: 200, maxWidth: 280)

                    filterLeadingGroup
                    filterTrailingGroup

                    if hasActiveFilters {
                        Button {
                            withAnimation {
                                licenseFilter = .all
                                editorialFilter = .all
                                groupingOption = .none
                                sortOption = .nameAsc
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(activeFilterCount) active")
                                    .font(.caption2.bold())
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Reset active filters")
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 6)

            if isSelectionMode, !packages.isEmpty {
                HStack(spacing: 12) {
                    Text("\(selectedPackageIDs.count) selected")
                        .font(.callout.bold())
                    Button("Select All") {
                        selectedPackageIDs = Set(packages.map(\.id))
                    }
                    .buttonStyle(.borderless)

                    Button("Deselect All") {
                        selectedPackageIDs.removeAll()
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    if !selectedPackages.isEmpty {
                        let installedSelected = selectedPackages.filter(\.isInstalled)
                        if !installedSelected.isEmpty {
                            let anyUnpinned = installedSelected.contains(where: { !BrewStorePackagePinningManager.shared.isPinned(packageID: $0.id) })
                            Button(anyUnpinned ? "Pin Selected (\(installedSelected.count))" : "Unpin Selected (\(installedSelected.count))") {
                                for pkg in installedSelected {
                                    if anyUnpinned {
                                        BrewStorePackagePinningManager.shared.pin(packageID: pkg.id, manager: manager)
                                    } else {
                                        BrewStorePackagePinningManager.shared.unpin(packageID: pkg.id, manager: manager)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(manager.isOperating)
                        }

                        let outdated = selectedPackages.filter(\.isOutdated)
                        if !outdated.isEmpty {
                            Button("Upgrade Selected (\(outdated.count))") {
                                BrewStoreActionReviewCoordinator.shared.requestUpgrade(packages: outdated, manager: manager) {
                                    for pkg in outdated {
                                        manager.perform(package: pkg, action: .upgrade)
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manager.isOperating)
                        }

                        Button("Uninstall Selected (\(selectedPackages.count))", role: .destructive) {
                            BrewStoreUninstallCoordinator.shared.requestUninstall(packages: selectedPackages, manager: manager)
                        }
                        .disabled(manager.isOperating)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))
            }

            if let lockMsg = manager.activeLockMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(lockMsg)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Cancel") {
                        manager.cancelCurrentOperation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            BrewStoreLockBanner(manager: manager)

            if !manager.statusMessage.isEmpty || manager.errorMessage != nil, !packages.isEmpty {
                HStack {
                    Text(manager.errorMessage ?? manager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(manager.errorMessage == nil ? Color.secondary : Color.red)
                        .textSelection(.enabled)
                    Spacer()
                    if manager.errorMessage != nil {
                        Button {
                            manager.retryRefresh()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(manager.isLoading || manager.isOperating)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            List {
                ForEach(groupedSections, id: \.title) { section in
                    if groupingOption != .none {
                        Section(header: Text(section.title).font(.headline).foregroundStyle(.primary)) {
                            packagesRows(for: section.packages)
                        }
                    } else {
                        packagesRows(for: section.packages)
                    }
                }
            }
            .accessibilityLabel("\(title) packages list, \(packages.count) total items")
            .searchable(text: $search, prompt: "Search \(title.lowercased())")
            .overlay {
                if manager.isLoading, packages.isEmpty {
                    ProgressView("Refreshing Homebrew…")
                } else if packages.isEmpty, let error = manager.errorMessage {
                    ContentUnavailableView {
                        Label(updatesOnly ? "Updates Unavailable" : "Catalog Refresh Issue", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button {
                            manager.retryRefresh()
                        } label: {
                            Label("Retry Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if packages.isEmpty, manager.errorMessage == nil {
                    if updatesOnly {
                        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasActiveFilters || selectedKindFilter != nil || showPinnedOnly {
                            ContentUnavailableView(
                                "No Updates Match Filter",
                                systemImage: "magnifyingglass",
                                description: Text("No pending updates match your search query or active filters.")
                            )
                        } else {
                            ContentUnavailableView(
                                "All Packages Up to Date",
                                systemImage: "checkmark.seal.fill",
                                description: Text("All installed packages are running their latest versions.")
                            )
                        }
                    } else {
                        ContentUnavailableView("No packages found", systemImage: "shippingbox", description: Text("Try adjusting your filters or search query."))
                    }
                }
            }
            .sheet(isPresented: $showingMASSheet) {
                MASView(manager: manager)
            }
            .detailModalOverlay(item: $selectedPackageForDetail) { package in
                PackageDetailView(manager: manager, package: package, onDismiss: {
                    selectedPackageForDetail = nil
                })
            }
            .overlay {
                if let ql = quickLookPackage {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture {
                                quickLookPackage = nil
                            }

                        BrewStoreQuickLookView(
                            package: ql,
                            manager: manager,
                            onOpenDetail: {
                                quickLookPackage = nil
                                selectedPackageForDetail = ql
                            },
                            onDismiss: {
                                quickLookPackage = nil
                            }
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .task {
                if installedOnly {
                    BrewStoreAppleSiliconMigrationManager.shared.scanMigrationCandidates(manager: manager)
                }
            }
        }
    }

    private func packagesRows(for list: [BrewStorePackage]) -> some View {
        ForEach(list) { package in
            if isSelectionMode {
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { selectedPackageIDs.contains(package.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedPackageIDs.insert(package.id)
                            } else {
                                selectedPackageIDs.remove(package.id)
                            }
                        }
                    )) {
                        PackageListRow(package: package, manager: manager)
                    }
                }
                .padding(.vertical, 2)
            } else {
                Button {
                    selectedPackageForDetail = package
                } label: {
                    PackageListRow(
                        package: package,
                        manager: manager,
                        onShowDetail: {
                            selectedPackageForDetail = package
                        },
                        onQuickLook: {
                            quickLookPackage = package
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filterLeadingGroup: some View {
        HStack(spacing: 8) {
            if kind == nil, !updatesOnly {
                Picker("Kind", selection: $selectedKindFilter) {
                    Text("All").tag(BrewPackageKind?.none)
                    Text("Apps").tag(Optional(BrewPackageKind.cask))
                    Text("CLI").tag(Optional(BrewPackageKind.formula))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
            }

            Menu {
                ForEach(PackageLicenseFilter.allCases) { item in
                    Button {
                        licenseFilter = item
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            } label: {
                Label(licenseFilter.rawValue, systemImage: licenseFilter.icon)
            }
            .controlSize(.small)

            Menu {
                ForEach(PackageEditorialFilter.allCases) { item in
                    Button {
                        editorialFilter = item
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            } label: {
                Label(editorialFilter.rawValue, systemImage: editorialFilter.icon)
            }
            .controlSize(.small)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var filterTrailingGroup: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(PackageGroupingOption.allCases) { item in
                    Button {
                        groupingOption = item
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            } label: {
                Label(groupingOption == .none ? "Group" : "Group: \(groupingOption.rawValue)", systemImage: groupingOption.icon)
            }
            .controlSize(.small)

            Menu {
                ForEach(PackageSortOption.allCases) { item in
                    Button {
                        sortOption = item
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            } label: {
                Label(sortOption == .nameAsc ? "Sort" : "Sort: \(sortOption.rawValue)", systemImage: sortOption.icon)
            }
            .controlSize(.small)

            if availableTaps.count > 1 {
                Picker("Tap", selection: $selectedTap) {
                    ForEach(availableTaps, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 140)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func chipView(title: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption2)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}

private struct PackageListRow: View {
    let package: BrewStorePackage
    @ObservedObject var manager: HomebrewManager
    var onShowDetail: (() -> Void)?
    var onQuickLook: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if package.kind == .cask,
               let icon = BrewStoreAppIconResolver.localAppIcon(for: package.applicationNames.isEmpty ? [package.name] : package.applicationNames) {
                Image(nsImage: icon)
                    .resizable().scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: package.kind == .cask ? "app.fill" : "terminal.fill")
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.tint)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    PackageInstallCountBadge(package: package)

                    if package.isInstalled {
                        PackageArchitectureBadge(
                            architecture: BrewStoreAppleSiliconMigrationManager.shared.architecture(for: package.id)
                        )
                    }
                }

                Text(package.description.isEmpty ? package.id : package.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if package.isOutdated {
                if BrewStoreVersionComparator.isMajorUpgrade(installed: package.installedVersion, latest: package.version) {
                    let summary = BrewStoreVersionComparator.majorUpgradeSummary(installed: package.installedVersion, latest: package.version) ?? "Major"
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(summary)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .help("Major version upgrade — may require configuration or database migrations.")
                }

                let est = BrewStoreUpdateEstimator.estimate(for: package)
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption)
                    Text("~\(est.formattedEstimate)")
                        .font(.caption.monospaced().weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.08), in: Capsule())
            }

            if let onQuickLook {
                Button {
                    onQuickLook()
                } label: {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.secondary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Quick Look Preview (Space)")
            }

            AppStoreActionButton(manager: manager, package: package, size: .small, onShowDetail: onShowDetail)
        }
        .padding(.vertical, 8)
        .brewStorePackageContextMenu(package: package, manager: manager, onShowDetails: onShowDetail, onQuickLook: onQuickLook)
    }
}

struct PackageInstallCountBadge: View {
    let packageID: String
    let kind: BrewPackageKind
    @ObservedObject private var analyticsManager = BrewStoreAnalyticsManager.shared

    init(package: BrewStorePackage) {
        self.packageID = package.id
        self.kind = package.kind
    }

    init(packageID: String, kind: BrewPackageKind) {
        self.packageID = packageID
        self.kind = kind
    }

    private var analytics: PackageInstallAnalytics? {
        analyticsManager.cachedOrBaseline(packageID: packageID, kind: kind)
    }

    var body: some View {
        if let analytics, analytics.install30d > 0 {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                Text("\(analytics.formatted30d)/mo")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.08), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .help("Install Statistics for \(packageID):\n• Last 7 days: \(analytics.formatted7d) (\(analytics.install7d.formatted()) installs)\n• Last 30 days (1 mo): \(analytics.formatted30d) (\(analytics.install30d.formatted()) installs)\n• Last 365 days (1 yr): \(analytics.formatted365d) (\(analytics.install365d.formatted()) installs)")
        }
    }
}
