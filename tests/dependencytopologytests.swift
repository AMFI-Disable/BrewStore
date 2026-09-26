@testable import BrewStore
import XCTest

final class DependencyTopologyTests: XCTestCase {
    func testEmptyPackagesYieldsEmptyTopology() {
        let topology = BrewStoreDependencyTopologyManager.analyze(packages: [])

        XCTAssertEqual(topology.totalPackagesInstalled, 0)
        XCTAssertEqual(topology.totalDependenciesMapped, 0)
        XCTAssertTrue(topology.sharedFoundations.isEmpty)
        XCTAssertTrue(topology.orphanLeaves.isEmpty)
        XCTAssertTrue(topology.linkageIssues.isEmpty)
        XCTAssertEqual(topology.orphanCount, 0)
        XCTAssertFalse(topology.hasOrphans)
    }

    func testOrphanLeavesAndSharedFoundationsClassification() {
        // Setup package graph:
        // - "openssl@3" (formula, installed, 0 deps) -> depended on by "curl" and "python" => Shared Foundation (count: 2)
        // - "zlib" (formula, installed, 0 deps) -> depended on by "curl" => Foundation (count: 1)
        // - "curl" (formula, installed, deps: ["openssl@3", "zlib"]) -> depended on by "git"
        // - "python" (formula, installed, deps: ["openssl@3"]) -> 0 dependents => Orphan Leaf!
        // - "git" (formula, installed, deps: ["curl"]) -> 0 dependents => Orphan Leaf!
        // - "raycast" (cask, installed, 0 deps) -> casks are not formula orphan leaves
        let openssl = BrewStorePackage(id: "openssl@3", name: "OpenSSL 3", description: "SSL toolkit", homepage: "", version: "3.0", kind: .formula, isInstalled: true, dependencies: [])
        let zlib = BrewStorePackage(id: "zlib", name: "zlib", description: "Compression library", homepage: "", version: "1.3", kind: .formula, isInstalled: true, dependencies: [])
        let curl = BrewStorePackage(id: "curl", name: "cURL", description: "Transfer URL data", homepage: "", version: "8.5", kind: .formula, isInstalled: true, dependencies: ["openssl@3", "zlib"])
        let python = BrewStorePackage(id: "python@3.12", name: "Python 3.12", description: "Programming language", homepage: "", version: "3.12", kind: .formula, isInstalled: true, dependencies: ["openssl@3"])
        let git = BrewStorePackage(id: "git", name: "Git", description: "Version control", homepage: "", version: "2.44", kind: .formula, isInstalled: true, dependencies: ["curl"])
        let raycast = BrewStorePackage(id: "raycast", name: "Raycast", description: "Launcher app", homepage: "", version: "1.70", kind: .cask, isInstalled: true, dependencies: [])

        let packages = [openssl, zlib, curl, python, git, raycast]
        let topology = BrewStoreDependencyTopologyManager.analyze(packages: packages)

        XCTAssertEqual(topology.totalPackagesInstalled, 6)
        XCTAssertEqual(topology.totalDependenciesMapped, 4) // curl (2) + python (1) + git (1)

        // Verify Shared Foundations
        XCTAssertTrue(topology.sharedFoundations.contains { $0.id == "openssl@3" && $0.dependentCount == 2 })
        XCTAssertTrue(topology.sharedFoundations.contains { $0.id == "zlib" && $0.dependentCount == 1 })
        XCTAssertTrue(topology.sharedFoundations.contains { $0.id == "curl" && $0.dependentCount == 1 })

        // Verify Orphan Leaves
        XCTAssertEqual(topology.orphanCount, 2)
        XCTAssertTrue(topology.hasOrphans)

        let orphanIDs = Set(topology.orphanLeaves.map(\.id))
        XCTAssertTrue(orphanIDs.contains("python@3.12"))
        XCTAssertTrue(orphanIDs.contains("git"))
        XCTAssertFalse(orphanIDs.contains("openssl@3"))
        XCTAssertFalse(orphanIDs.contains("curl"))
        XCTAssertFalse(orphanIDs.contains("raycast")) // Casks excluded from formula orphan leaves
    }

    func testBrokenLinkageDetectionForMissingDependencies() {
        // "ripgrep" installed, depends on "pcre2" which is NOT installed
        let ripgrep = BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "Fast grep", homepage: "", version: "14.1", kind: .formula, isInstalled: true, dependencies: ["pcre2"])
        let pcre2 = BrewStorePackage(id: "pcre2", name: "PCRE2", description: "Regex library", homepage: "", version: "10.42", kind: .formula, isInstalled: false, dependencies: [])

        let topology = BrewStoreDependencyTopologyManager.analyze(packages: [ripgrep, pcre2])

        XCTAssertEqual(topology.linkageIssues.count, 1)
        let issue = topology.linkageIssues.first
        XCTAssertEqual(issue?.id, "ripgrep->pcre2")
        XCTAssertEqual(issue?.binaryPath, "ripgrep")
        XCTAssertEqual(issue?.severity, "warning")
        XCTAssertTrue(issue?.reason.contains("pcre2") == true)
    }

    func testDeduplicationAndUniqueOrphanIDs() {
        // Duplicate records in package array
        let orphan1 = BrewStorePackage(id: "bat", name: "Bat", description: "Cat with wings", homepage: "", version: "0.24", kind: .formula, isInstalled: true, dependencies: [])
        let orphan2 = BrewStorePackage(id: "bat", name: "Bat", description: "Cat with wings", homepage: "", version: "0.24", kind: .formula, isInstalled: true, dependencies: [])

        let topology = BrewStoreDependencyTopologyManager.analyze(packages: [orphan1, orphan2])

        XCTAssertEqual(topology.orphanLeaves.count, 1)
        XCTAssertEqual(topology.orphanLeaves.first?.id, "bat")
    }

    @MainActor
    func testTopologyManagerAsyncAnalysis() async {
        let manager = HomebrewManager()
        let topologyManager = BrewStoreDependencyTopologyManager.shared

        topologyManager.analyzeTopology(manager: manager)
        XCTAssertTrue(topologyManager.isAnalyzing)

        // Wait briefly for detached task to complete
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(topologyManager.isAnalyzing)
        XCTAssertNotNil(topologyManager.topology)
    }

    func testParseAutoremoveOutputFormats() {
        // Format 1: Modern Homebrew dry-run multi-line
        let output1 = """
        ==> Would uninstall 2 unneeded formulae:
        libevent
        libidn2
        """
        let parsed1 = BrewStoreUninstallCoordinator.parseAutoremoveOutput(output1)
        XCTAssertEqual(parsed1, ["libevent", "libidn2"])
        XCTAssertFalse(parsed1.contains("formulae:"))

        // Format 2: Comma-separated autoremoved output
        let output2 = "==> Autoremoved 3 unneeded dependencies:\n  libevent, libidn2, utf8proc\n"
        let parsed2 = BrewStoreUninstallCoordinator.parseAutoremoveOutput(output2)
        XCTAssertEqual(parsed2, ["libevent", "libidn2", "utf8proc"])

        // Format 3: Legacy or live uninstalling lines
        let output3 = """
        Uninstalling libevent...
        Uninstalling libidn2...
        """
        let parsed3 = BrewStoreUninstallCoordinator.parseAutoremoveOutput(output3)
        XCTAssertEqual(parsed3, ["libevent", "libidn2"])

        // Format 4: Empty / Nothing to autoremove
        let output4 = ""
        let parsed4 = BrewStoreUninstallCoordinator.parseAutoremoveOutput(output4)
        XCTAssertTrue(parsed4.isEmpty)
    }

    func testDependencyTreeCalculatorPreIndexedGraph() {
        let openssl = BrewStorePackage(id: "openssl@3", name: "OpenSSL 3", description: "", homepage: "", version: "3.0", kind: .formula, isInstalled: true, dependencies: [])
        let curl = BrewStorePackage(id: "curl", name: "cURL", description: "", homepage: "", version: "8.5", kind: .formula, isInstalled: true, dependencies: ["openssl@3"])
        let git = BrewStorePackage(id: "git", name: "Git", description: "", homepage: "", version: "2.44", kind: .formula, isInstalled: true, dependencies: ["curl"])

        let graph = DependencyTreeCalculator.buildGraph(for: curl, in: [openssl, curl, git])
        XCTAssertEqual(graph.rootID, "curl")
        XCTAssertEqual(graph.upstreamNodes.count, 1)
        XCTAssertEqual(graph.upstreamNodes.first?.id, "openssl@3")
        XCTAssertEqual(graph.downstreamNodes.count, 1)
        XCTAssertEqual(graph.downstreamNodes.first?.id, "git")
        XCTAssertTrue(graph.hasDependents)
    }

    func testRecursiveDependencyTreeBuilderWithCycleDetection() {
        let cmake = BrewStorePackage(id: "cmake", name: "CMake", description: "Build tool", homepage: "", version: "3.28", kind: .formula, isInstalled: true, dependencies: [])
        let openssl = BrewStorePackage(id: "openssl@3", name: "OpenSSL 3", description: "Crypto", homepage: "", version: "3.2.1", kind: .formula, isInstalled: true, dependencies: [])
        let curl = BrewStorePackage(id: "curl", name: "curl", description: "URL transfer", homepage: "", version: "8.5", kind: .formula, isInstalled: true, dependencies: ["openssl@3", "cmake"])
        let app = BrewStorePackage(id: "my-app", name: "My App", description: "App", homepage: "", version: "1.0", kind: .formula, isInstalled: true, dependencies: ["curl"])

        let all = [cmake, openssl, curl, app]
        let rootNode = DependencyTreeBuilder.buildRecursiveTree(for: app, in: all)

        XCTAssertEqual(rootNode.packageID, "my-app")
        XCTAssertEqual(rootNode.depth, 0)
        XCTAssertEqual(rootNode.children.count, 1)

        let curlNode = rootNode.children.first
        XCTAssertEqual(curlNode?.packageID, "curl")
        XCTAssertEqual(curlNode?.depth, 1)
        XCTAssertEqual(curlNode?.children.count, 2)

        let cmakeNode = curlNode?.children.first { $0.packageID == "cmake" }
        XCTAssertNotNil(cmakeNode)
        XCTAssertTrue(cmakeNode?.isBuildOnly == true)
        XCTAssertFalse(cmakeNode?.isCycle == true)

        let opensslNode = curlNode?.children.first { $0.packageID == "openssl@3" }
        XCTAssertNotNil(opensslNode)
        XCTAssertFalse(opensslNode?.isBuildOnly == true)

        // Verify cycle detection: create a cyclical dependency (pkgA -> pkgB -> pkgA)
        let pkgA = BrewStorePackage(id: "pkgA", name: "pkgA", description: "", homepage: "", version: "1.0", kind: .formula, isInstalled: true, dependencies: ["pkgB"])
        let pkgB = BrewStorePackage(id: "pkgB", name: "pkgB", description: "", homepage: "", version: "1.0", kind: .formula, isInstalled: true, dependencies: ["pkgA"])
        let cycleTree = DependencyTreeBuilder.buildRecursiveTree(for: pkgA, in: [pkgA, pkgB])
        XCTAssertEqual(cycleTree.packageID, "pkgA")
        let bNode = cycleTree.children.first
        XCTAssertEqual(bNode?.packageID, "pkgB")
        let cycleNode = bNode?.children.first
        XCTAssertEqual(cycleNode?.packageID, "pkgA")
        XCTAssertTrue(cycleNode?.isCycle == true)
        XCTAssertTrue(cycleNode?.children.isEmpty == true) // Halts cycle recursion
    }

    func testSimulateUninstallBlastRadiusWithTransitiveCascade() {
        // openssl@3 -> curl -> git -> gh
        let openssl = BrewStorePackage(id: "openssl@3", name: "openssl@3", description: "", homepage: "", version: "3.2", kind: .formula, isInstalled: true, dependencies: [])
        let curl = BrewStorePackage(id: "curl", name: "curl", description: "", homepage: "", version: "8.5", kind: .formula, isInstalled: true, dependencies: ["openssl@3"])
        let git = BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.44", kind: .formula, isInstalled: true, dependencies: ["curl"])
        let gh = BrewStorePackage(id: "gh", name: "gh", description: "", homepage: "", version: "2.45", kind: .formula, isInstalled: true, dependencies: ["git"])

        let all = [openssl, curl, git, gh]
        let blast = BrewStorePreFlightDependencyChecker.simulateUninstallBlastRadius(package: openssl, in: all)

        XCTAssertTrue(blast.isDestructive)
        // Direct broken is just curl
        XCTAssertEqual(blast.brokenDownstreamPackages, ["curl"])
        // Transitive broken contains curl, git, and gh
        XCTAssertEqual(Set(blast.transitiveBrokenPackages), Set(["curl", "git", "gh"]))
        // Risk level is critical since >= 3 packages broken
        XCTAssertEqual(blast.riskLevel, .critical)
        XCTAssertEqual(blast.impactSeverity, "critical")
    }

    func testSimulateUninstallBlastRadiusWithRunningServices() {
        let pcre2 = BrewStorePackage(id: "pcre2", name: "pcre2", description: "", homepage: "", version: "10.42", kind: .formula, isInstalled: true, dependencies: [])
        let nginx = BrewStorePackage(id: "nginx", name: "nginx", description: "Web server", homepage: "", version: "1.25", kind: .formula, isInstalled: true, dependencies: ["pcre2"])

        let nginxService = BrewStoreService(id: "nginx", name: "nginx", status: "started", user: "even", file: nil)
        XCTAssertTrue(nginxService.isRunning)

        let all = [pcre2, nginx]
        let blast = BrewStorePreFlightDependencyChecker.simulateUninstallBlastRadius(
            package: pcre2,
            in: all,
            services: [nginxService]
        )

        XCTAssertTrue(blast.isDestructive)
        XCTAssertEqual(blast.brokenDownstreamPackages, ["nginx"])
        XCTAssertEqual(blast.affectedRunningServices.count, 1)
        XCTAssertEqual(blast.affectedRunningServices.first?.name, "nginx")
        XCTAssertEqual(blast.riskLevel, .critical)
    }

    func testMultiVersionCoexistenceDetection() {
        let openssl1 = BrewStorePackage(id: "openssl@1.1", name: "OpenSSL 1.1", description: "", homepage: "", version: "1.1.1w", kind: .formula, isInstalled: true, dependencies: [])
        let openssl3 = BrewStorePackage(id: "openssl@3", name: "OpenSSL 3", description: "", homepage: "", version: "3.2.1", kind: .formula, isInstalled: true, dependencies: [])
        let curl = BrewStorePackage(id: "curl", name: "curl", description: "", homepage: "", version: "8.5", kind: .formula, isInstalled: true, dependencies: ["openssl@3"])
        let standalone = BrewStorePackage(id: "bat", name: "bat", description: "", homepage: "", version: "0.24", kind: .formula, isInstalled: true, dependencies: [])

        let all = [openssl1, openssl3, curl, standalone]
        let topology = BrewStoreDependencyTopologyManager.analyze(packages: all)

        XCTAssertEqual(topology.coexistenceCount, 1)
        let group = topology.versionCoexistenceGroups.first
        XCTAssertEqual(group?.id, "openssl")
        XCTAssertEqual(group?.installedVersions.count, 2)
        XCTAssertTrue(group?.hasUnusedVersion == true)
        XCTAssertEqual(group?.unusedVersionIDs, ["openssl@1.1"])

        // Divergent dependents
        XCTAssertEqual(group?.divergentDependents["openssl@1.1"], [])
        XCTAssertEqual(group?.divergentDependents["openssl@3"], ["curl"])
    }

    func testBuildBaggageScavengerDetection() {
        let cmake = BrewStorePackage(id: "cmake", name: "cmake", description: "Build tool", homepage: "", version: "3.28", kind: .formula, isInstalled: true, dependencies: [])
        let ninja = BrewStorePackage(id: "ninja", name: "ninja", description: "Build tool", homepage: "", version: "1.11", kind: .formula, isInstalled: true, dependencies: [])
        let ripgrep = BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "Grep", homepage: "", version: "14.1", kind: .formula, isInstalled: true, dependencies: ["ninja"])

        // cmake has 0 dependents -> Build Baggage!
        // ninja has 1 dependent (ripgrep) -> In active use, NOT baggage!
        let all = [cmake, ninja, ripgrep]
        let topology = BrewStoreDependencyTopologyManager.analyze(packages: all)

        XCTAssertEqual(topology.buildBaggageCount, 1)
        let baggage = topology.buildBaggagePackages.first
        XCTAssertEqual(baggage?.id, "cmake")
        XCTAssertEqual(baggage?.category, "Build System")
        XCTAssertTrue(baggage?.reason.contains("build tool") == true)
    }

    func testGraphvizDotExportGeneration() {
        let openssl = BrewStorePackage(id: "openssl@3", name: "openssl@3", description: "", homepage: "", version: "3.0", kind: .formula, isInstalled: true, dependencies: [])
        let curl = BrewStorePackage(id: "curl", name: "curl", description: "", homepage: "", version: "8.5", kind: .formula, isInstalled: true, dependencies: ["openssl@3"])

        let dot = BrewStoreLockfileGenerator.generateGraphvizDot(packages: [openssl, curl])

        XCTAssertTrue(dot.contains("digraph BrewStoreDependencies {"))
        XCTAssertTrue(dot.contains("rankdir=LR;"))
        XCTAssertTrue(dot.contains("\"curl\" -> \"openssl@3\";"))
        XCTAssertTrue(dot.hasSuffix("}"))
    }
}
