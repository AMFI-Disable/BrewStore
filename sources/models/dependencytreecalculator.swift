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
