import Foundation

struct SharedFoundationLibrary: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let dependentCount: Int
    let dependentPackageIDs: [String]
    let isInstalled: Bool
}

struct OrphanLeafPackage: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let description: String
    let kind: BrewPackageKind
    let isOrphanCandidate: Bool
}

struct BrokenLinkageIssue: Identifiable, Hashable, Codable {
    let id: String
    let binaryPath: String
    let reason: String
    let severity: String // "warning", "critical"
}

struct VersionCoexistenceGroup: Identifiable, Hashable, Codable {
    let id: String // Family root name, e.g. "openssl", "python", "node"
    let familyName: String
    let installedVersions: [BrewStorePackage]
    let totalDiskBytes: Int64
    let formattedTotalDiskSize: String
    let divergentDependents: [String: [String]] // Version ID -> [Dependent Names]
    let hasUnusedVersion: Bool
    let unusedVersionIDs: [String]
}

struct BuildBaggagePackage: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let version: String
    let diskBytes: Int64
    let formattedDiskSize: String
    let category: String
    let reason: String
}

struct SystemDependencyTopology: Hashable, Codable {
    let totalPackagesInstalled: Int
    let totalDependenciesMapped: Int
    let sharedFoundations: [SharedFoundationLibrary]
    let orphanLeaves: [OrphanLeafPackage]
    let linkageIssues: [BrokenLinkageIssue]
    let versionCoexistenceGroups: [VersionCoexistenceGroup]
    let buildBaggagePackages: [BuildBaggagePackage]

    var orphanCount: Int {
        orphanLeaves.count
    }

    var hasOrphans: Bool {
        !orphanLeaves.isEmpty
    }

    var coexistenceCount: Int {
        versionCoexistenceGroups.count
    }

    var buildBaggageCount: Int {
        buildBaggagePackages.count
    }

    var totalReclaimableBuildBaggageBytes: Int64 {
        buildBaggagePackages.reduce(0) { $0 + $1.diskBytes }
    }

    var formattedReclaimableBuildBaggage: String {
        ByteCountFormatter.string(fromByteCount: totalReclaimableBuildBaggageBytes, countStyle: .file)
    }
}

enum TopologyTab: String, CaseIterable, Identifiable, Codable {
    case foundations = "Core Shared Libraries"
    case orphans = "Unused Dependencies"
    case integrity = "Binary Health & Linkage"
    case coexistence = "Version Coexistence"
    case buildBaggage = "Build Baggage"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .foundations: "pyramid.fill"
        case .orphans: "leaf.fill"
        case .integrity: "checkmark.shield.fill"
        case .coexistence: "square.split.2x2.fill"
        case .buildBaggage: "wrench.and.screwdriver.fill"
        }
    }
}

@MainActor
final class BrewStoreDependencyTopologyManager: ObservableObject {
    static let shared = BrewStoreDependencyTopologyManager()

    @Published var topology: SystemDependencyTopology?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var lastAnalyzed: Date?
    @Published var selectedTab: TopologyTab = .foundations

    private var lastAnalyzedPackageCount: Int?

    func ensureTopologyUpdated(manager: HomebrewManager) {
        guard !isAnalyzing else { return }
        let installedCount = manager.packages.filter(\.isInstalled).count
        if topology == nil || lastAnalyzedPackageCount != installedCount {
            analyzeTopology(manager: manager)
        }
    }

    func analyzeTopology(manager: HomebrewManager) {
        let packages = manager.packages
        let installed = packages.filter(\.isInstalled)

        if let err = manager.errorMessage, installed.isEmpty {
            if topology == nil {
                self.errorMessage = "Unable to analyze dependencies: \(err)"
            }
            return
        }

        isAnalyzing = true
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            let result = Self.analyze(packages: packages)
            await MainActor.run {
                self.topology = result
                self.lastAnalyzed = Date()
                self.lastAnalyzedPackageCount = installed.count
                self.isAnalyzing = false
            }
        }
    }

    nonisolated static func analyze(packages: [BrewStorePackage]) -> SystemDependencyTopology {
        let installed = packages.filter(\.isInstalled)
        let packageMap = Dictionary(packages.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // 1. Build Reverse Dependency Map: DepID -> [ParentIDs]
        var reverseMap: [String: Set<String>] = [:]
        var totalMappedDeps = 0

        for pkg in installed {
            for dep in pkg.dependencies {
                let depLower = dep.lowercased()
                reverseMap[depLower, default: []].insert(pkg.id)
                totalMappedDeps += 1
            }
        }

        // 2. Shared Foundation Libraries (depended on by at least 2 packages)
        var sharedFoundations: [SharedFoundationLibrary] = []
        for (depID, dependents) in reverseMap {
            let depPkg = packageMap[depID]
            sharedFoundations.append(SharedFoundationLibrary(
                id: depID,
                name: depPkg?.name ?? depID,
                dependentCount: dependents.count,
                dependentPackageIDs: Array(dependents).sorted(),
                isInstalled: depPkg?.isInstalled ?? false
            ))
        }
        sharedFoundations.sort { $0.dependentCount > $1.dependentCount }

        // 3. Orphan Leaves: Installed packages that are NOT depended on by ANY other installed package
        var orphanLeaves: [OrphanLeafPackage] = []
        var seenOrphanIDs = Set<String>()
        for pkg in installed {
            let depCount = reverseMap[pkg.id.lowercased()]?.count ?? 0
            if depCount == 0, pkg.kind == .formula {
                let key = pkg.id.lowercased()
                if !seenOrphanIDs.contains(key) {
                    seenOrphanIDs.insert(key)
                    orphanLeaves.append(OrphanLeafPackage(
                        id: pkg.id,
                        name: pkg.name,
                        description: pkg.description,
                        kind: pkg.kind,
                        isOrphanCandidate: true
                    ))
                }
            }
        }
        orphanLeaves.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // 4. Linkage & Integrity Issues: Check for missing dependencies
        var linkageIssues: [BrokenLinkageIssue] = []
        for pkg in installed {
            for dep in pkg.dependencies {
                let depPkg = packageMap[dep.lowercased()]
                if depPkg == nil || depPkg?.isInstalled == false {
                    linkageIssues.append(BrokenLinkageIssue(
                        id: "\(pkg.id)->\(dep)",
                        binaryPath: pkg.name,
                        reason: "Missing dependency: '\(dep)' required by \(pkg.name) is not installed",
                        severity: "warning"
                    ))
                }
            }
        }

        // 5. Multi-Version Coexistence: Installed packages with multiple major versions
        var familyGroups: [String: [BrewStorePackage]] = [:]
        for pkg in installed where pkg.kind == .formula {
            let cleanID = (pkg.id.components(separatedBy: "/").last ?? pkg.id).lowercased()
            let family = cleanID.components(separatedBy: "@").first ?? cleanID
            familyGroups[family, default: []].append(pkg)
        }

        var versionCoexistenceGroups: [VersionCoexistenceGroup] = []
        for (family, familyPackages) in familyGroups where familyPackages.count >= 2 {
            let sortedPackages = familyPackages.sorted {
                $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
            var divergentMap: [String: [String]] = [:]
            var unusedIDs: [String] = []
            var familyDiskBytes: Int64 = 0

            for pkg in sortedPackages {
                let deps = reverseMap[pkg.id.lowercased()] ?? []
                let depNames = deps.compactMap { packageMap[$0.lowercased()]?.name ?? $0 }.sorted()
                divergentMap[pkg.id] = depNames
                if depNames.isEmpty {
                    unusedIDs.append(pkg.id)
                }
                if let cellar = pkg.cellarURL() {
                    familyDiskBytes += BrewStoreDiskStorageAnalyzerManager.computeDirectorySize(url: cellar)
                }
            }

            let group = VersionCoexistenceGroup(
                id: family,
                familyName: family.capitalized,
                installedVersions: sortedPackages,
                totalDiskBytes: familyDiskBytes,
                formattedTotalDiskSize: ByteCountFormatter.string(fromByteCount: familyDiskBytes, countStyle: .file),
                divergentDependents: divergentMap,
                hasUnusedVersion: !unusedIDs.isEmpty,
                unusedVersionIDs: unusedIDs
            )
            versionCoexistenceGroups.append(group)
        }
        versionCoexistenceGroups.sort {
            if $0.totalDiskBytes != $1.totalDiskBytes {
                return $0.totalDiskBytes > $1.totalDiskBytes
            }
            return $0.familyName.localizedStandardCompare($1.familyName) == .orderedAscending
        }

        // 6. Build Baggage Scavenger: Packages installed solely as build tools with 0 current dependents
        var buildBaggagePackages: [BuildBaggagePackage] = []
        for pkg in installed where pkg.kind == .formula {
            if HomebrewBuildToolHeuristics.isBuildOnly(id: pkg.id) {
                let depCount = reverseMap[pkg.id.lowercased()]?.count ?? 0
                if depCount == 0 {
                    var pkgBytes: Int64 = 0
                    if let cellar = pkg.cellarURL() {
                        pkgBytes = BrewStoreDiskStorageAnalyzerManager.computeDirectorySize(url: cellar)
                    }
                    let category = HomebrewBuildToolHeuristics.buildCategory(for: pkg.id)
                    buildBaggagePackages.append(BuildBaggagePackage(
                        id: pkg.id,
                        name: pkg.name,
                        version: pkg.displayInstalledVersion ?? pkg.displayVersion,
                        diskBytes: pkgBytes,
                        formattedDiskSize: ByteCountFormatter.string(fromByteCount: pkgBytes, countStyle: .file),
                        category: category,
                        reason: "Installed as a build tool (\(category)), currently required by 0 installed formulae."
                    ))
                }
            }
        }
        buildBaggagePackages.sort {
            if $0.diskBytes != $1.diskBytes {
                return $0.diskBytes > $1.diskBytes
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        return SystemDependencyTopology(
            totalPackagesInstalled: installed.count,
            totalDependenciesMapped: totalMappedDeps,
            sharedFoundations: sharedFoundations,
            orphanLeaves: orphanLeaves,
            linkageIssues: linkageIssues,
            versionCoexistenceGroups: versionCoexistenceGroups,
            buildBaggagePackages: buildBaggagePackages
        )
    }
}
