import AppKit
import Combine
import SwiftUI

enum BrewStoreUninstallOperation: Equatable {
    case packages
    case autoremove

    var title: String {
        switch self {
        case .packages: "Uninstall Package"
        case .autoremove: "Clean Unused Dependencies"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .packages: "Confirm Uninstall"
        case .autoremove: "Confirm Cleanup"
        }
    }
}

struct BrewStoreUninstallRequest: Identifiable {
    let id = UUID()
    var packages: [BrewStorePackage]
    let impacts: [UninstallBlastRadius]
    let operation: BrewStoreUninstallOperation
    var removalPlans: [BrewStoreRemovalPlan] = []
    var isScanningResiduals: Bool = false
    fileprivate let manager: HomebrewManager
    fileprivate let onCompletion: ((Bool) -> Void)?

    var packageNames: [String] {
        packages.map(\.name)
    }

    var brokenDownstreamPackages: [String] {
        Self.uniqueSorted(impacts.flatMap(\.brokenDownstreamPackages))
    }

    var orphanableDependencies: [String] {
        Self.uniqueSorted(impacts.flatMap(\.orphanableDependencies))
    }

    var safeSharedDependencies: [String] {
        Self.uniqueSorted(impacts.flatMap(\.safeSharedDependencies))
    }

    var isDestructive: Bool {
        !brokenDownstreamPackages.isEmpty
    }

    var totalResidualBytes: Int64 {
        removalPlans.reduce(0) { $0 + $1.selectedBytes }
    }

    var formattedTotalResidualBytes: String {
        ByteCountFormatter.string(fromByteCount: totalResidualBytes, countStyle: .file)
    }

    var totalResidualCount: Int {
        removalPlans.reduce(0) { $0 + $1.selectedCount }
    }

    var hasResiduals: Bool {
        totalResidualCount > 0
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

@MainActor
final class BrewStoreUninstallCoordinator: ObservableObject {
    static let shared = BrewStoreUninstallCoordinator()

    @Published var pendingRequest: BrewStoreUninstallRequest?

    private let executeUninstall: (HomebrewManager, [BrewStorePackage], @escaping (Bool) -> Void) -> Void
    private let executeAutoremove: (HomebrewManager) -> Void
    private let executeTrash: ((BrewStoreRemovalPlan) -> BrewStoreRemovalResult)?

    init(
        executeUninstall: ((HomebrewManager, [BrewStorePackage]) -> Void)? = nil,
        executeAutoremove: ((HomebrewManager) -> Void)? = nil,
        executeTrash: ((BrewStoreRemovalPlan) -> BrewStoreRemovalResult)? = nil
    ) {
        self.executeUninstall = { manager, packages, completion in
            if let executeUninstall {
                executeUninstall(manager, packages)
                completion(true)
                return
            }

            if packages.count == 1, let package = packages.first {
                manager.perform(package: package, action: .uninstall, completion: completion)
            } else {
                manager.batchPerform(packages: packages, action: .uninstall) { results in
                    completion(results.count == packages.count && results.values.allSatisfy { $0 })
                }
            }
        }
        self.executeAutoremove = executeAutoremove ?? { manager in
            manager.autoremove()
        }
        self.executeTrash = executeTrash
    }

    func requestUninstall(package: BrewStorePackage, manager: HomebrewManager, onCompletion: ((Bool) -> Void)? = nil) {
        requestUninstall(packages: [package], manager: manager, onCompletion: onCompletion)
    }

    func requestUninstall(packages: [BrewStorePackage], manager: HomebrewManager, onCompletion: ((Bool) -> Void)? = nil) {
        let installedPackages = resolvedInstalledPackages(packages, manager: manager)
        guard !installedPackages.isEmpty else {
            onCompletion?(true)
            return
        }

        var request = makeRequest(
            packages: installedPackages,
            operation: .packages,
            manager: manager,
            onCompletion: onCompletion
        )

        let hasCasks = installedPackages.contains { $0.kind == .cask }
        let cleanerEnabled = BrewStorePreferences.shared.enableAppCleaner
        if hasCasks, cleanerEnabled {
            request.isScanningResiduals = true
        }

        pendingRequest = request

        if hasCasks, cleanerEnabled {
            let requestId = request.id
            Task { [weak self] in
                let plans = await Self.scanResidualPlans(for: installedPackages)
                guard let self, var current = self.pendingRequest, current.id == requestId else { return }
                current.removalPlans = plans
                current.isScanningResiduals = false
                self.pendingRequest = current
            }
        }
    }

    /// Presents a preview for Homebrew's autoremove operation.
    func requestAutoremove(manager: HomebrewManager) {
        requestAutoremove(packages: [], manager: manager)
    }

    func requestAutoremove(packages: [BrewStorePackage], manager: HomebrewManager) {
        let installedPackages = resolvedInstalledPackages(packages, manager: manager)
        var request = makeRequest(
            packages: installedPackages,
            operation: .autoremove,
            manager: manager
        )

        if installedPackages.isEmpty {
            request.isScanningResiduals = true
        }

        pendingRequest = request

        if installedPackages.isEmpty {
            let requestId = request.id
            Task { [weak self] in
                let orphans = await Self.scanOrphanCandidates(manager: manager)
                guard let self, var current = self.pendingRequest, current.id == requestId else { return }
                current.packages = orphans
                current.isScanningResiduals = false
                self.pendingRequest = current
            }
        }
    }

    func cancel() {
        pendingRequest?.onCompletion?(false)
        pendingRequest = nil
    }

    func confirm(selectedResidualURLs: Set<URL>? = nil) {
        guard let request = pendingRequest else { return }
        let manager = request.manager

        guard !manager.isOperating else {
            cancel()
            return
        }

        if request.operation == .packages, !manager.packages.isEmpty {
            let requestIsStillInstalled = request.packages.allSatisfy { requested in
                if let resolved = manager.packages.first(where: {
                    $0.id.caseInsensitiveCompare(requested.id) == .orderedSame && $0.kind == requested.kind
                }) {
                    return resolved.isInstalled
                }
                return requested.isInstalled
            }
            guard requestIsStillInstalled else {
                manager.statusMessage = "Uninstall cancelled because the package state changed. Refresh and try again."
                cancel()
                return
            }
        }

        // Collect residual files to trash
        var plansToTrash: [BrewStoreRemovalPlan] = []
        for plan in request.removalPlans {
            let filteredCandidates = plan.candidates.filter { candidate in
                if let selectedURLs = selectedResidualURLs {
                    return selectedURLs.contains(candidate.url)
                }
                return candidate.isSelected
            }
            if !filteredCandidates.isEmpty {
                var modifiedPlan = plan
                modifiedPlan.candidates = filteredCandidates
                plansToTrash.append(modifiedPlan)
            }
        }

        let totalTrashBytes = plansToTrash.reduce(0) { $0 + $1.selectedBytes }
        let packageNames = request.packageNames.joined(separator: ", ")

        pendingRequest = nil
        switch request.operation {
        case .packages:
            executeUninstall(manager, request.packages) { [weak self] success in
                if success, !plansToTrash.isEmpty {
                    self?.executeResidualTrash(plans: plansToTrash)
                    let formattedBytes = ByteCountFormatter.string(fromByteCount: totalTrashBytes, countStyle: .file)
                    manager.statusMessage = "Uninstalled \(packageNames) and moved \(formattedBytes) of residual files to Trash."
                }
                request.onCompletion?(success)
            }
        case .autoremove:
            executeAutoremove(manager)
        }
    }

    private func executeResidualTrash(plans: [BrewStoreRemovalPlan]) {
        if let customTrash = executeTrash {
            for plan in plans {
                _ = customTrash(plan)
            }
            return
        }

        Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let allowedRoots: [URL] = [
                home.appendingPathComponent("Library/Application Support"),
                home.appendingPathComponent("Library/Caches"),
                home.appendingPathComponent("Library/Containers"),
                home.appendingPathComponent("Library/Group Containers"),
                home.appendingPathComponent("Library/Preferences"),
                home.appendingPathComponent("Library/Logs"),
                URL(fileURLWithPath: "/Applications"),
                home.appendingPathComponent("Applications")
            ]
            let validator = BrewStorePathSafetyValidator(allowedRoots: allowedRoots)
            let executor = BrewStoreTrashExecutor(validator: validator)
            for plan in plans {
                _ = executor.execute(plan: plan)
            }
        }
    }

    private func makeRequest(
        packages: [BrewStorePackage],
        operation: BrewStoreUninstallOperation,
        manager: HomebrewManager,
        onCompletion: ((Bool) -> Void)? = nil
    ) -> BrewStoreUninstallRequest {
        let impacts = Self.dependencyImpacts(for: packages, in: manager.packages)
        return BrewStoreUninstallRequest(
            packages: packages,
            impacts: impacts,
            operation: operation,
            manager: manager,
            onCompletion: onCompletion
        )
    }

    static func dependencyImpacts(for packages: [BrewStorePackage], in allPackages: [BrewStorePackage]) -> [UninstallBlastRadius] {
        packages.map {
            BrewStorePreFlightDependencyChecker.simulateUninstallBlastRadius(package: $0, in: allPackages)
        }
    }

    static func scanResidualPlans(for packages: [BrewStorePackage]) async -> [BrewStoreRemovalPlan] {
        let casks = packages.filter { $0.kind == .cask }
        guard !casks.isEmpty else { return [] }

        return await Task.detached(priority: .userInitiated) {
            var plans: [BrewStoreRemovalPlan] = []
            let scanner = BrewStoreAppRemovalScanner()

            for pkg in casks {
                let names = pkg.applicationNames.isEmpty ? [pkg.name] : pkg.applicationNames
                let targetURL = await MainActor.run {
                    BrewStoreAppIconResolver.localAppURL(for: names)
                } ?? URL(fileURLWithPath: "/Applications/\(names.first ?? pkg.name).app")

                let bundleID = (Bundle(url: targetURL)?.bundleIdentifier) ?? "com.\(pkg.id)"
                let identity = BrewStoreAppIdentity(
                    name: targetURL.deletingPathExtension().lastPathComponent,
                    bundleIdentifier: bundleID,
                    applicationURL: targetURL
                )

                let plan = scanner.scan(application: identity)
                if !plan.candidates.isEmpty {
                    plans.append(plan)
                }
            }
            return plans
        }.value
    }

    static func scanOrphanCandidates(manager: HomebrewManager) async -> [BrewStorePackage] {
        await Task.detached(priority: .userInitiated) {
            let brewPath = await MainActor.run { manager.brewPath ?? "/opt/homebrew/bin/brew" }
            let autoResult = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["autoremove", "-n"],
                timeout: 30,
                category: .readOnly
            )

            var orphanNames: [String] = []
            if autoResult.succeeded {
                orphanNames = Self.parseAutoremoveOutput(autoResult.standardOutput)
            }
            let finalOrphanNames = orphanNames
            return await MainActor.run {
                finalOrphanNames.compactMap { name in
                    manager.packages.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ??
                        BrewStorePackage(
                            id: name,
                            name: name,
                            description: "Unneeded dependency formula",
                            homepage: "",
                            version: "",
                            kind: .formula,
                            isInstalled: true
                        )
                }
            }
        }.value
    }

    nonisolated static func parseAutoremoveOutput(_ output: String) -> [String] {
        var orphanNames: [String] = []
        var isInPackageList = false

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let isHeader = (line.localizedCaseInsensitiveContains("uninstall") || line.localizedCaseInsensitiveContains("autoremov")) &&
                (line.hasSuffix(":") || line.localizedCaseInsensitiveContains("unneeded") || line.localizedCaseInsensitiveContains("formulae") || line.localizedCaseInsensitiveContains("dependencies"))
            if isHeader {
                isInPackageList = true
                continue
            }

            if line.hasPrefix("Uninstalling ") {
                let rest = line.dropFirst("Uninstalling ".count).trimmingCharacters(in: .whitespaces)
                let candidate = rest.replacingOccurrences(of: "...", with: "").split(separator: " ").first.map(String.init) ?? ""
                let cleaned = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "():,."))
                if !cleaned.isEmpty && !cleaned.localizedCaseInsensitiveContains("formula") && !cleaned.localizedCaseInsensitiveContains("unneeded") {
                    orphanNames.append(cleaned)
                }
                continue
            }

            if isInPackageList {
                if line.hasPrefix("==>") && !line.localizedCaseInsensitiveContains("uninstall") && !line.localizedCaseInsensitiveContains("autoremov") {
                    isInPackageList = false
                    continue
                }
                if line.contains(",") {
                    for part in line.split(separator: ",") {
                        let candidate = part.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "():,.")))
                        if !candidate.isEmpty && !candidate.hasPrefix("==") && !candidate.localizedCaseInsensitiveContains("formula") {
                            orphanNames.append(candidate)
                        }
                    }
                } else {
                    let candidate = line.split(separator: " ").first.map(String.init) ?? ""
                    let cleaned = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "():,."))
                    if !cleaned.isEmpty && !cleaned.hasPrefix("==") && !cleaned.localizedCaseInsensitiveContains("formula") {
                        orphanNames.append(cleaned)
                    }
                }
            }
        }
        return Array(Set(orphanNames)).sorted()
    }

    private func resolvedInstalledPackages(_ packages: [BrewStorePackage], manager: HomebrewManager) -> [BrewStorePackage] {
        var seen = Set<String>()
        return packages.compactMap { requested in
            let resolved = manager.packages.first {
                $0.id.caseInsensitiveCompare(requested.id) == .orderedSame && $0.kind == requested.kind
            } ?? requested
            guard resolved.isInstalled else { return nil }
            let key = Self.packageKey(resolved)
            guard seen.insert(key).inserted else { return nil }
            return resolved
        }
    }

    private static func packageKey(_ package: BrewStorePackage) -> String {
        "\(package.kind.rawValue):\(package.id.lowercased())"
    }
}

extension BrewStoreRemovalCandidateKind {
    var displayName: String {
        switch self {
        case .applicationBundle: "App Bundle"
        case .applicationSupport: "Application Support"
        case .cache: "Caches & Data"
        case .container: "Sandbox Container"
        case .groupContainer: "Group Container"
        case .preference: "Preferences"
        case .helperTool: "Helper Tool"
        case .log: "Logs"
        case .unknown: "Residual"
        }
    }

    var systemImage: String {
        switch self {
        case .applicationBundle: "app.fill"
        case .applicationSupport: "folder.fill.badge.gear"
        case .cache: "internaldrive"
        case .container, .groupContainer: "shippingbox.fill"
        case .preference: "slider.horizontal.3"
        case .helperTool: "wrench.and.screwdriver"
        case .log: "doc.text.fill"
        case .unknown: "questionmark.folder"
        }
    }

    var iconColor: Color {
        switch self {
        case .applicationBundle: .blue
        case .applicationSupport: .indigo
        case .cache: .orange
        case .container, .groupContainer: .teal
        case .preference: .purple
        case .helperTool: .yellow
        case .log: .gray
        case .unknown: .secondary
        }
    }
}

struct BrewStoreUninstallPreviewView: View {
    let request: BrewStoreUninstallRequest
    let onConfirm: () -> Void
    var onConfirmSelection: ((Set<URL>) -> Void)?
    let onCancel: () -> Void

    @State private var selectedCandidateURLs: Set<URL> = []

    init(
        request: BrewStoreUninstallRequest,
        onConfirm: @escaping () -> Void,
        onConfirmSelection: ((Set<URL>) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onConfirm = onConfirm
        self.onConfirmSelection = onConfirmSelection
        self.onCancel = onCancel

        var initialURLs = Set<URL>()
        for plan in request.removalPlans {
            for candidate in plan.candidates where candidate.isSelected {
                initialURLs.insert(candidate.url)
            }
        }
        _selectedCandidateURLs = State(initialValue: initialURLs)
    }

    private var allCandidates: [BrewStoreRemovalCandidate] {
        request.removalPlans.flatMap(\.candidates)
    }

    private var selectedCandidates: [BrewStoreRemovalCandidate] {
        allCandidates.filter { selectedCandidateURLs.contains($0.url) }
    }

    private var totalSelectedResidualBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.size }
    }

    private var formattedSelectedResidualBytes: String {
        ByteCountFormatter.string(fromByteCount: totalSelectedResidualBytes, countStyle: .file)
    }

    private var totalOrphanCellarBytes: Int64 {
        let prefix = request.manager.brewPrefix ?? "/opt/homebrew"
        return request.packages.reduce(0) { total, pkg in
            let path = URL(fileURLWithPath: "\(prefix)/Cellar/\(pkg.name)")
            return total + BrewStoreDiskStorageAnalyzerManager.computeDirectorySize(url: path)
        }
    }

    private var formattedOrphanCellarBytes: String {
        ByteCountFormatter.string(fromByteCount: totalOrphanCellarBytes, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    packagesSection

                    dependencyImpactSection

                    if request.operation == .packages {
                        residualFilesSection
                    } else if request.operation == .autoremove {
                        orphanBreakdownSection
                    }
                }
            }

            Divider()

            bottomActionBar
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            syncInitialSelection()
        }
        .onChange(of: request.removalPlans.count) { _, _ in
            syncInitialSelection()
        }
    }

    private func syncInitialSelection() {
        for plan in request.removalPlans {
            for candidate in plan.candidates where candidate.isSelected {
                selectedCandidateURLs.insert(candidate.url)
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 14) {
            headerIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.title2.bold())
                Text(requestSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var headerIcon: some View {
        Group {
            if request.isDestructive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if request.operation == .autoremove {
                Image(systemName: "broom.fill")
                    .foregroundStyle(.blue)
            } else if !request.removalPlans.isEmpty {
                Image(systemName: "trash.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 32))
    }

    private var headerTitle: String {
        if request.operation == .autoremove {
            return "Review Dependency Cleanup"
        }
        if !request.removalPlans.isEmpty {
            return "Review Uninstall & Leftover Cleanup"
        }
        return "Review Uninstall"
    }

    private var requestSubtitle: String {
        switch request.operation {
        case .packages:
            if request.packages.count == 1 {
                return "Confirm the dependency impact and residual files before removing."
            }
            return "Confirm the dependency impact and residual files for \(request.packages.count) packages."
        case .autoremove:
            return "Review unused dependency candidates before Homebrew purges them."
        }
    }

    @ViewBuilder
    private var packagesSection: some View {
        if !request.packages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(request.operation == .packages ? "Packages to Remove" : "Orphan Formulas Identified")
                    .font(.headline)
                ForEach(request.packages) { package in
                    HStack(spacing: 10) {
                        Image(systemName: package.kind == .cask ? "app.fill" : "terminal.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(package.name)
                            .fontWeight(.medium)
                        Text(package.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let version = package.displayInstalledVersion ?? package.displayVersion.nilIfEmpty {
                            Text(version)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var dependencyImpactSection: some View {
        if request.isDestructive {
            warningCard(title: "High-Impact Dependency Warning", color: .red) {
                let targetName = request.packages.first?.name ?? "these packages"
                Text("Installed packages depend on \(targetName). Removing them may break those tools:")
                Text(request.brokenDownstreamPackages.joined(separator: ", "))
                    .font(.caption.bold())
            }
        } else if !request.orphanableDependencies.isEmpty {
            warningCard(title: "Potential Orphan Dependencies", color: .orange) {
                Text("These dependency packages may become orphanable after the operation:")
                Text(request.orphanableDependencies.joined(separator: ", "))
                    .font(.caption.bold())
            }
        } else if request.operation == .packages {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text("Safe uninstall: No other installed packages depend on this software.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        if !request.safeSharedDependencies.isEmpty {
            let retained = request.safeSharedDependencies.joined(separator: ", ")
            Text("Shared dependencies retained: \(retained)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var residualFilesSection: some View {
        if request.isScanningResiduals {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning for leftover application data & caches…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        } else if !request.removalPlans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("App Residuals & Leftover Data", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    if totalSelectedResidualBytes > 0 {
                        Text("\(selectedCandidates.count) items · \(formattedSelectedResidualBytes)")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    Button(selectedCandidates.count == allCandidates.count ? "Deselect All" : "Select All") {
                        if selectedCandidates.count == allCandidates.count {
                            selectedCandidateURLs.removeAll()
                        } else {
                            selectedCandidateURLs = Set(allCandidates.map(\.url))
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                VStack(spacing: 6) {
                    ForEach(allCandidates) { candidate in
                        HStack(spacing: 10) {
                            Toggle(isOn: Binding(
                                get: { selectedCandidateURLs.contains(candidate.url) },
                                set: { isChecked in
                                    if isChecked {
                                        selectedCandidateURLs.insert(candidate.url)
                                    } else {
                                        selectedCandidateURLs.remove(candidate.url)
                                    }
                                }
                            )) {
                                EmptyView()
                            }
                            .labelsHidden()

                            Image(systemName: candidate.kind.systemImage)
                                .foregroundStyle(candidate.kind.iconColor)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.kind.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text(displayPath(candidate.url))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Text(candidate.formattedSize)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedCandidateURLs.contains(candidate.url) ? Color.orange.opacity(0.06) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var orphanBreakdownSection: some View {
        if request.isScanningResiduals {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Analyzing dependencies with Homebrew autoremove…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        } else if request.packages.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Orphaned Dependencies Found")
                        .font(.headline)
                    Text("All installed formulas are required by other packages or were directly requested.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("Homebrew will prune \(request.packages.count) unneeded dependencies (\(formattedOrphanCellarBytes)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bottomActionBar: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(confirmButtonTitle, role: .destructive) {
                if let onConfirmSelection {
                    onConfirmSelection(selectedCandidateURLs)
                } else {
                    onConfirm()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(request.operation == .autoremove && request.packages.isEmpty && !request.isScanningResiduals)
        }
    }

    private var confirmButtonTitle: String {
        if request.operation == .packages {
            if totalSelectedResidualBytes > 0 {
                return "Uninstall & Clean (\(formattedSelectedResidualBytes))"
            }
            return "Uninstall Package"
        }
        if request.packages.isEmpty {
            return "Nothing to Clean"
        }
        return "Purge \(request.packages.count) Orphan\(request.packages.count == 1 ? "" : "s")"
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let full = url.path
        if full.hasPrefix(home) {
            return "~" + full.dropFirst(home.count)
        }
        return full
    }

    private func warningCard(title: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(color)
            content()
                .font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 1))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
