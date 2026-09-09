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
}
