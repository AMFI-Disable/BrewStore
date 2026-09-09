import Foundation

struct SnapshotRollbackPlan: Identifiable, Hashable, Codable {
    let id: String
    let snapshotID: String
    let snapshotDate: Date
    let packagesToUninstall: [String] // Installed now, but wasn't in snapshot
    let packagesToReinstall: [String] // In snapshot, but missing now

    var totalOperations: Int {
        packagesToUninstall.count + packagesToReinstall.count
    }

    var isEmpty: Bool {
        totalOperations == 0
    }
}

@MainActor
final class BrewStoreSnapshotRollbackManager: ObservableObject {
    static let shared = BrewStoreSnapshotRollbackManager()

    @Published var isRollingBack = false
    @Published var statusMessage = ""

    func computePlan(currentPackages: [BrewStorePackage], snapshot: BrewStoreSnapshot) -> SnapshotRollbackPlan {
        let currentlyInstalledIDs = Set(currentPackages.filter(\.isInstalled).map { $0.id.lowercased() })
        let snapshotIDs = snapshot.formulae + snapshot.casks
        let snapshotPackageIDs = Set(snapshotIDs.map { $0.lowercased() })

        let toUninstall = currentlyInstalledIDs.subtracting(snapshotPackageIDs).sorted()
        let toReinstall = snapshotPackageIDs.subtracting(currentlyInstalledIDs).sorted()

        return SnapshotRollbackPlan(
            id: UUID().uuidString,
            snapshotID: snapshot.id,
            snapshotDate: snapshot.timestamp,
            packagesToUninstall: toUninstall,
            packagesToReinstall: toReinstall
        )
    }

    func executeRollback(plan: SnapshotRollbackPlan, manager: HomebrewManager, completion: (@Sendable @MainActor (Bool) -> Void)? = nil) {
        guard !isRollingBack, !plan.isEmpty else {
            completion?(true)
            return
        }

        isRollingBack = true
        statusMessage = "Starting Time Machine rollback to snapshot from \(plan.snapshotDate.formatted())…"

        Task { @MainActor [weak self] in
            // 1. Uninstall newly added packages
            let packagesToUninstall = plan.packagesToUninstall.compactMap { pkgID in
                manager.packages.first(where: { $0.id.lowercased() == pkgID && $0.isInstalled })
            }
            if !packagesToUninstall.isEmpty {
                self?.statusMessage = "Reviewing packages to uninstall before rollback…"
                let uninstallSucceeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    BrewStoreUninstallCoordinator.shared.requestUninstall(packages: packagesToUninstall, manager: manager) { succeeded in
                        continuation.resume(returning: succeeded)
                    }
                }
                guard uninstallSucceeded else {
                    self?.isRollingBack = false
                    self?.statusMessage = "Rollback cancelled before package removal."
                    completion?(false)
                    return
                }
            }

            // 2. Reinstall missing packages
            for pkgID in plan.packagesToReinstall {
                self?.statusMessage = "Restoring: reinstalling \(pkgID)…"
                let targetPkg = manager.packages.first(where: { $0.id.lowercased() == pkgID }) ??
                    BrewStorePackage(id: pkgID, name: pkgID, description: "", homepage: "", version: "", kind: .formula)

                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    manager.perform(package: targetPkg, action: .install) { _ in
                        continuation.resume()
                    }
                }
            }

            self?.isRollingBack = false
            self?.statusMessage = "Rollback complete! Restored system state to \(plan.snapshotDate.formatted())."
            manager.refresh()
            completion?(true)
        }
    }
}
