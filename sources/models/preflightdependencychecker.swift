import Foundation

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

struct UninstallBlastRadius: Hashable, Codable {
    let packageID: String
    let packageName: String
    let brokenDownstreamPackages: [String]
    let orphanableDependencies: [String]
    let safeSharedDependencies: [String]
    let isDestructive: Bool

    var impactSeverity: String {
        if brokenDownstreamPackages.count >= 3 {
            "high"
        } else if !brokenDownstreamPackages.isEmpty {
            "medium"
        } else {
            "low"
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

    static func simulateUninstallBlastRadius(package: BrewStorePackage, in allPackages: [BrewStorePackage]) -> UninstallBlastRadius {
        let installed = allPackages.filter(\.isInstalled)
        let packageMap = Dictionary(allPackages.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // 1. Find all installed packages that directly or transitively depend on this package
        var broken: [String] = []
        for pkg in installed where pkg.id != package.id {
            if pkg.dependencies.map({ $0.lowercased() }).contains(package.id.lowercased()) {
                broken.append(pkg.name)
            }
        }

        // 2. Inspect dependencies of the package being uninstalled
        var orphanable: [String] = []
        var safeShared: [String] = []

        for depID in package.dependencies {
            let depLower = depID.lowercased()
            // Check if any other installed package depends on this dep
            let otherDependents = installed.filter { other in
                other.id != package.id && other.dependencies.map { $0.lowercased() }.contains(depLower)
            }

            if otherDependents.isEmpty {
                orphanable.append(packageMap[depLower]?.name ?? depID)
            } else {
                safeShared.append(packageMap[depLower]?.name ?? depID)
            }
        }

        let isDestructive = !broken.isEmpty

        return UninstallBlastRadius(
            packageID: package.id,
            packageName: package.name,
            brokenDownstreamPackages: broken.sorted(),
            orphanableDependencies: orphanable.sorted(),
            safeSharedDependencies: safeShared.sorted(),
            isDestructive: isDestructive
        )
    }
}
