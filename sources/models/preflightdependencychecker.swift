import Foundation
import SwiftUI

struct PreInstallSimulation: Hashable, Codable {
    let packageID: String
    let packageName: String
    let missingDependencies: [String]
    let alreadyInstalledDependencies: [String]
    let conflicts: [String]
    let isSafeToInstall: Bool

    var totalDependenciesCount: Int {
        missingDependencies.count + alreadyInstalledDependencies.count
    }

    var requiresAdditionalDownloads: Bool {
        !missingDependencies.isEmpty
    }
}

enum RemovalRiskLevel: String, CaseIterable, Codable {
    case zero = "Zero Risk"
    case moderate = "Moderate Risk"
    case critical = "Critical Risk"

    var badgeColor: Color {
        switch self {
        case .zero: .green
        case .moderate: .orange
        case .critical: .red
        }
    }

    var icon: String {
        switch self {
        case .zero: "checkmark.shield.fill"
        case .moderate: "exclamationmark.triangle.fill"
        case .critical: "bolt.trianglebadge.exclamationmark.fill"
        }
    }
}

struct UninstallBlastRadius: Hashable, Codable {
    let packageID: String
    let packageName: String
    let brokenDownstreamPackages: [String]
    let transitiveBrokenPackages: [String]
    let orphanableDependencies: [String]
    let safeSharedDependencies: [String]
    let affectedRunningServices: [BrewStoreService]
    let riskLevel: RemovalRiskLevel
    let isDestructive: Bool

    var impactSeverity: String {
        switch riskLevel {
        case .critical:
            return "critical"
        case .moderate:
            return "medium"
        case .zero:
            return "low"
        }
    }
}

enum BrewStorePreFlightDependencyChecker {
    static func simulatePreInstall(package: BrewStorePackage, in allPackages: [BrewStorePackage]) -> PreInstallSimulation {
        let packageMap = Dictionary(allPackages.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        var missing: [String] = []
        var installed: [String] = []
        var conflicts: [String] = []

        var visited = Set<String>()
        var queue = package.dependencies

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let lower = current.lowercased()
            guard !visited.contains(lower) else { continue }
            visited.insert(lower)

            if let depPkg = packageMap[lower] {
                if depPkg.isInstalled {
                    installed.append(depPkg.name)
                } else {
                    missing.append(depPkg.name)
                }
                for subDep in depPkg.dependencies {
                    queue.append(subDep)
                }
            } else {
                missing.append(current)
            }
        }

        // Check for conflicting pinned versions
        for depName in missing + installed {
            if let depPkg = packageMap[depName.lowercased()], depPkg.isPinned {
                conflicts.append("Dependency '\(depPkg.name)' is pinned to v\(depPkg.version); install may require unpinning.")
            }
        }

        let isSafe = conflicts.isEmpty

        return PreInstallSimulation(
            packageID: package.id,
            packageName: package.name,
            missingDependencies: missing.sorted(),
            alreadyInstalledDependencies: installed.sorted(),
            conflicts: conflicts,
            isSafeToInstall: isSafe
        )
    }

    static func simulateUninstallBlastRadius(
        package: BrewStorePackage,
        in allPackages: [BrewStorePackage],
        services: [BrewStoreService] = []
    ) -> UninstallBlastRadius {
        let installed = allPackages.filter(\.isInstalled)
        let packageMap = Dictionary(allPackages.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // 1. Build reverse dependency index: DepID -> [Installed Packages]
        var reverseIndex: [String: [BrewStorePackage]] = [:]
        for pkg in installed {
            for dep in pkg.dependencies {
                let depLower = dep.lowercased()
                reverseIndex[depLower, default: []].append(pkg)
                let baseDep = (dep.components(separatedBy: "/").last ?? dep).lowercased()
                if baseDep != depLower {
                    reverseIndex[baseDep, default: []].append(pkg)
                }
            }
        }

        // 2. Direct downstream dependents
        let targetLower = package.id.lowercased()
        let directDependents = reverseIndex[targetLower] ?? []
        let directBrokenNames = directDependents.map(\.name)

        // 3. Transitive downstream closure via BFS
        var transitiveBrokenMap: [String: String] = [:] // ID -> Name
        for dep in directDependents {
            transitiveBrokenMap[dep.id.lowercased()] = dep.name
        }

        var queue: [String] = directDependents.map { $0.id.lowercased() }
        var visited = Set<String>([targetLower])
        for q in queue {
            visited.insert(q)
        }

        while !queue.isEmpty {
            let currentID = queue.removeFirst()
            let nextLevel = reverseIndex[currentID] ?? []
            for nextPkg in nextLevel {
                let nextLower = nextPkg.id.lowercased()
                if !visited.contains(nextLower) {
                    visited.insert(nextLower)
                    transitiveBrokenMap[nextLower] = nextPkg.name
                    queue.append(nextLower)
                }
            }
        }

        // 4. Identify impacted running services
        var impactedServices: [BrewStoreService] = []
        let runningServices = services.filter(\.isRunning)
        let allImpactedIDs = Set([targetLower] + transitiveBrokenMap.keys)

        for srv in runningServices {
            let srvID = srv.id.lowercased()
            let srvName = srv.name.lowercased()
            if allImpactedIDs.contains(srvID) || allImpactedIDs.contains(srvName) {
                impactedServices.append(srv)
            }
        }

        // 5. Inspect dependencies of the package being uninstalled
        var orphanable: [String] = []
        var safeShared: [String] = []

        for depID in package.dependencies {
            let depLower = depID.lowercased()
            // Check if any other installed package (outside the removal tree) depends on this dep
            let otherDependents = installed.filter { other in
                other.id.lowercased() != targetLower &&
                !allImpactedIDs.contains(other.id.lowercased()) &&
                other.dependencies.map { $0.lowercased() }.contains(depLower)
            }

            if otherDependents.isEmpty {
                orphanable.append(packageMap[depLower]?.name ?? depID)
            } else {
                safeShared.append(packageMap[depLower]?.name ?? depID)
            }
        }

        let transitiveBrokenNames = Array(Set(transitiveBrokenMap.values)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

        // 6. Calculate Risk Assessment Level
        let riskLevel: RemovalRiskLevel
        if !impactedServices.isEmpty || transitiveBrokenNames.count >= 3 {
            riskLevel = .critical
        } else if !transitiveBrokenNames.isEmpty {
            riskLevel = .moderate
        } else {
            riskLevel = .zero
        }

        let isDestructive = !transitiveBrokenNames.isEmpty || !impactedServices.isEmpty

        return UninstallBlastRadius(
            packageID: package.id,
            packageName: package.name,
            brokenDownstreamPackages: Array(Set(directBrokenNames)).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            transitiveBrokenPackages: transitiveBrokenNames,
            orphanableDependencies: Array(Set(orphanable)).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            safeSharedDependencies: Array(Set(safeShared)).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            affectedRunningServices: impactedServices,
            riskLevel: riskLevel,
            isDestructive: isDestructive
        )
    }
}
