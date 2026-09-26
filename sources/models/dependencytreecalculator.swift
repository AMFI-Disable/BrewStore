import Foundation

struct DependencyNode: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let kind: BrewPackageKind
    let isInstalled: Bool
    let depth: Int
    let dependencies: [String]
    let dependents: [String]
}

struct DependencyGraphModel: Hashable, Codable {
    let rootID: String
    let rootName: String
    let upstreamNodes: [DependencyNode]
    let downstreamNodes: [DependencyNode]
    let hasDependents: Bool

    var totalNodeCount: Int {
        1 + upstreamNodes.count + downstreamNodes.count
    }
}

enum DependencyTreeCalculator {
    static func buildGraph(for root: BrewStorePackage, in allPackages: [BrewStorePackage]) -> DependencyGraphModel {
        let packageMap = Dictionary(allPackages.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // 1. Traverse Upstream (Dependencies required by root)
        var upstream: [DependencyNode] = []
        var visitedUpstream = Set<String>()
        var queue: [(id: String, depth: Int)] = root.dependencies.map { ($0, 1) }

        while !queue.isEmpty {
            let (currentID, depth) = queue.removeFirst()
            let lowerID = currentID.lowercased()
            guard !visitedUpstream.contains(lowerID), lowerID != root.id.lowercased() else { continue }
            visitedUpstream.insert(lowerID)

            let pkg = packageMap[lowerID]
            let node = DependencyNode(
                id: currentID,
                name: pkg?.name ?? currentID,
                kind: pkg?.kind ?? .formula,
                isInstalled: pkg?.isInstalled ?? false,
                depth: depth,
                dependencies: pkg?.dependencies ?? [],
                dependents: pkg?.dependents ?? []
            )
            upstream.append(node)

            if depth < 3, let directDeps = pkg?.dependencies {
                for nextDep in directDeps {
                    queue.append((nextDep, depth + 1))
                }
            }
        }

        // 2. Traverse Downstream (Packages that require root)
        // Pre-index reverse dependencies for O(1) lookup across large catalogs
        var reverseIndex: [String: [BrewStorePackage]] = [:]
        for pkg in allPackages {
            for dep in pkg.dependencies {
                let depLower = dep.lowercased()
                reverseIndex[depLower, default: []].append(pkg)
                let normalized = (dep.components(separatedBy: "/").last ?? dep).lowercased()
                if normalized != depLower {
                    reverseIndex[normalized, default: []].append(pkg)
                }
            }
        }

        var downstream: [DependencyNode] = []
        var visitedDownstream = Set<String>()
        let directDependents = reverseIndex[root.id.lowercased()] ?? []
        var downQueue: [(pkg: BrewStorePackage, depth: Int)] = directDependents.map { ($0, 1) }

        while !downQueue.isEmpty {
            let (currentPkg, depth) = downQueue.removeFirst()
            let lowerID = currentPkg.id.lowercased()
            guard !visitedDownstream.contains(lowerID), lowerID != root.id.lowercased() else { continue }
            visitedDownstream.insert(lowerID)

            let node = DependencyNode(
                id: currentPkg.id,
                name: currentPkg.name,
                kind: currentPkg.kind,
                isInstalled: currentPkg.isInstalled,
                depth: depth,
                dependencies: currentPkg.dependencies,
                dependents: currentPkg.dependents
            )
            downstream.append(node)

            if depth < 3 {
                let nextLevel = reverseIndex[lowerID] ?? []
                for nextPkg in nextLevel {
                    downQueue.append((nextPkg, depth + 1))
                }
            }
        }

        return DependencyGraphModel(
            rootID: root.id,
            rootName: root.name,
            upstreamNodes: upstream.sorted { $0.depth < $1.depth },
            downstreamNodes: downstream.sorted { $0.depth < $1.depth },
            hasDependents: !downstream.isEmpty
        )
    }
}

enum HomebrewBuildToolHeuristics {
    static let knownBuildToolIDs: Set<String> = [
        "cmake", "ninja", "pkg-config", "pkgconf", "meson", "autoconf",
        "automake", "bison", "m4", "libtool", "nasm", "yasm", "doxygen",
        "sphinx-doc", "swig", "gnu-sed", "flex", "help2man", "gettext",
        "docbook", "docbook-xsl", "asciidoctor", "berkeley-db", "scons",
        "make", "gnu-which"
    ]

    static func isBuildOnly(id: String) -> Bool {
        let cleanID = (id.components(separatedBy: "/").last ?? id).lowercased()
        let baseName = cleanID.components(separatedBy: "@").first ?? cleanID
        return knownBuildToolIDs.contains(cleanID) || knownBuildToolIDs.contains(baseName)
    }

    static func buildCategory(for id: String) -> String {
        let cleanID = (id.components(separatedBy: "/").last ?? id).lowercased()
        let baseName = cleanID.components(separatedBy: "@").first ?? cleanID

        switch baseName {
        case "cmake", "ninja", "meson", "scons", "make":
            return "Build System"
        case "pkg-config", "pkgconf":
            return "Package Configurator"
        case "autoconf", "automake", "m4", "libtool":
            return "Autotools Suite"
        case "bison", "flex", "swig":
            return "Code & Parser Generator"
        case "nasm", "yasm":
            return "Assembler"
        case "doxygen", "sphinx-doc", "asciidoctor", "docbook", "docbook-xsl":
            return "Documentation Generator"
        default:
            return "Build Dependency"
        }
    }
}

struct DependencyTreeNode: Identifiable, Hashable, Codable {
    let id: String
    let packageID: String
    let name: String
    let version: String
    let kind: BrewPackageKind
    let isInstalled: Bool
    let isBuildOnly: Bool
    let depth: Int
    let children: [DependencyTreeNode]
    let isCycle: Bool

    var totalChildrenCount: Int {
        children.reduce(children.count) { $0 + $1.totalChildrenCount }
    }
}

enum DependencyTreeBuilder {
    static func buildRecursiveTree(
        for rootPackage: BrewStorePackage,
        in allPackages: [BrewStorePackage],
        maxDepth: Int = 5
    ) -> DependencyTreeNode {
        let packageMap = Dictionary(allPackages.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var currentAncestors = Set<String>()
        return buildNode(
            packageID: rootPackage.id,
            depth: 0,
            packageMap: packageMap,
            ancestors: &currentAncestors,
            maxDepth: maxDepth
        )
    }

    private static func buildNode(
        packageID: String,
        depth: Int,
        packageMap: [String: BrewStorePackage],
        ancestors: inout Set<String>,
        maxDepth: Int
    ) -> DependencyTreeNode {
        let lowerID = packageID.lowercased()
        let resolved = packageMap[lowerID]
        let name = resolved?.name ?? packageID
        let version = resolved?.displayInstalledVersion ?? resolved?.displayVersion ?? ""
        let kind = resolved?.kind ?? .formula
        let isInstalled = resolved?.isInstalled ?? false
        let isBuildOnly = HomebrewBuildToolHeuristics.isBuildOnly(id: packageID)

        if ancestors.contains(lowerID) {
            return DependencyTreeNode(
                id: "\(packageID)-depth\(depth)-cycle",
                packageID: packageID,
                name: name,
                version: version,
                kind: kind,
                isInstalled: isInstalled,
                isBuildOnly: isBuildOnly,
                depth: depth,
                children: [],
                isCycle: true
            )
        }

        if depth >= maxDepth {
            return DependencyTreeNode(
                id: "\(packageID)-depth\(depth)",
                packageID: packageID,
                name: name,
                version: version,
                kind: kind,
                isInstalled: isInstalled,
                isBuildOnly: isBuildOnly,
                depth: depth,
                children: [],
                isCycle: false
            )
        }

        ancestors.insert(lowerID)
        let childIDs = resolved?.dependencies ?? []
        var children: [DependencyTreeNode] = []
        for childID in childIDs {
            children.append(buildNode(
                packageID: childID,
                depth: depth + 1,
                packageMap: packageMap,
                ancestors: &ancestors,
                maxDepth: maxDepth
            ))
        }
        ancestors.remove(lowerID)

        return DependencyTreeNode(
            id: "\(packageID)-depth\(depth)-\(children.count)",
            packageID: packageID,
            name: name,
            version: version,
            kind: kind,
            isInstalled: isInstalled,
            isBuildOnly: isBuildOnly,
            depth: depth,
            children: children,
            isCycle: false
        )
    }
}
