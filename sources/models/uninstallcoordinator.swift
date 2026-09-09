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
    let packages: [BrewStorePackage]
    let impacts: [UninstallBlastRadius]
    let operation: BrewStoreUninstallOperation
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

    init(
        executeUninstall: ((HomebrewManager, [BrewStorePackage]) -> Void)? = nil,
        executeAutoremove: ((HomebrewManager) -> Void)? = nil
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

        pendingRequest = makeRequest(
            packages: installedPackages,
            operation: .packages,
            manager: manager,
            onCompletion: onCompletion
        )
    }

    /// Presents a preview for Homebrew's autoremove operation. When topology has
    /// identified the candidates, pass them in so their dependency impact is shown.
    func requestAutoremove(manager: HomebrewManager) {
        requestAutoremove(packages: [], manager: manager)
    }

    func requestAutoremove(packages: [BrewStorePackage], manager: HomebrewManager) {
        let installedPackages = resolvedInstalledPackages(packages, manager: manager)
        pendingRequest = makeRequest(
            packages: installedPackages,
            operation: .autoremove,
            manager: manager
        )
    }

    func cancel() {
        pendingRequest?.onCompletion?(false)
        pendingRequest = nil
    }

    func confirm() {
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

        pendingRequest = nil
        switch request.operation {
        case .packages:
            executeUninstall(manager, request.packages) { success in
                request.onCompletion?(success)
            }
        case .autoremove:
            executeAutoremove(manager)
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

struct BrewStoreUninstallPreviewView: View {
    let request: BrewStoreUninstallRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: request.isDestructive ? "exclamationmark.triangle.fill" : "shippingbox.fill")
                    .font(.title)
                    .foregroundStyle(request.isDestructive ? .red : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.operation == .packages ? "Review Uninstall" : "Review Dependency Cleanup")
                        .font(.title2.bold())
                    Text(requestSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !request.packages.isEmpty {
                        impactSection(title: request.operation == .packages ? "Packages to remove" : "Likely cleanup candidates") {
                            ForEach(request.packages) { package in
                                Label {
                                    Text(package.name)
                                    Text(package.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: package.kind == .cask ? "app.fill" : "terminal.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if request.isDestructive {
                        warningSection(title: "High-impact dependency warning", color: .red) {
                            let targetName = request.packages.first?.name ?? "these packages"
                            Text("Installed packages depend on \(targetName). Removing them may break those tools.")
                            Text(request.brokenDownstreamPackages.joined(separator: ", "))
                                .font(.caption.bold())
                        }
                    } else if !request.orphanableDependencies.isEmpty {
                        warningSection(title: "Dependency impact", color: .orange) {
                            Text("These dependency packages may become orphanable after the operation:")
                            Text(request.orphanableDependencies.joined(separator: ", "))
                                .font(.caption.bold())
                        }
                    } else if request.operation == .autoremove, request.packages.isEmpty {
                        warningSection(title: "Homebrew-managed cleanup", color: .blue) {
                            Text("Homebrew will determine the unused dependency set at execution time. No package will be removed until you confirm.")
                        }
                    } else {
                        Label("No installed dependents or orphanable dependencies were detected.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    if !request.safeSharedDependencies.isEmpty {
                        let retained = request.safeSharedDependencies.joined(separator: ", ")
                        Text("Shared dependencies retained: \(retained)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(request.operation.confirmationTitle, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
    }

    private var requestSubtitle: String {
        switch request.operation {
        case .packages:
            request.packages.count == 1 ? "Confirm the dependency impact before Homebrew runs." : "Confirm the dependency impact before Homebrew removes these packages."
        case .autoremove:
            "Review the cleanup scope before Homebrew runs autoremove."
        }
    }

    private func impactSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 7, content: content)
        }
    }

    private func warningSection(title: String, color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
