@testable import BrewStore
import XCTest

@MainActor
final class LockfileGeneratorTests: XCTestCase {
    func testLockfileGenerationDeterministicOutput() {
        let curl = BrewStorePackage(id: "curl", name: "cURL", description: "", homepage: "", version: "8.5.0", kind: .formula, isInstalled: true, dependencies: ["openssl@3", "zlib"])
        let openssl = BrewStorePackage(id: "openssl@3", name: "OpenSSL 3", description: "", homepage: "", version: "3.0.0", kind: .formula, isInstalled: true, dependencies: [])
        let raycast = BrewStorePackage(id: "raycast", name: "Raycast", description: "", homepage: "", version: "1.70.0", kind: .cask, isInstalled: true, dependencies: [])

        let packages = [curl, openssl, raycast]
        let taps = [
            BrewStoreTap(id: "homebrew/core", name: "homebrew/core"),
            BrewStoreTap(id: "homebrew/cask", name: "homebrew/cask")
        ]

        let doc = BrewStoreLockfileGenerator.generateLockfile(packages: packages, taps: taps)

        XCTAssertEqual(doc.schemaVersion, "1.0.0")
        XCTAssertEqual(doc.totalPackages, 3)
        XCTAssertEqual(doc.taps, ["homebrew/cask", "homebrew/core"])
        XCTAssertEqual(doc.entries.count, 3)

        let curlEntry = doc.entries.first { $0.id == "curl" }
        XCTAssertNotNil(curlEntry)
        XCTAssertEqual(curlEntry?.version, "8.5.0")
        XCTAssertEqual(curlEntry?.dependencies, ["openssl@3", "zlib"])

        let jsonString = BrewStoreLockfileGenerator.generateJSONString(packages: packages, taps: taps)
        XCTAssertTrue(jsonString.contains("\"totalPackages\" : 3"))
        XCTAssertTrue(jsonString.contains("\"schemaVersion\" : \"1.0.0\""))
        XCTAssertTrue(jsonString.contains("curl"))
    }

    func testMermaidGraphGeneration() {
        let curl = BrewStorePackage(id: "curl", name: "cURL", description: "", homepage: "", version: "8.5.0", kind: .formula, isInstalled: true, dependencies: ["openssl@3"])
        let graph = BrewStoreLockfileGenerator.generateMermaidGraph(packages: [curl])

        XCTAssertTrue(graph.starts(with: "graph TD"))
        XCTAssertTrue(graph.contains("curl[\"cURL\"] --> openssl_3[\"openssl@3\"]"))
    }

    func testMarkdownTreeGeneration() {
        let curl = BrewStorePackage(id: "curl", name: "cURL", description: "", homepage: "", version: "8.5.0", kind: .formula, isInstalled: true, dependencies: ["openssl@3"])
        let tree = BrewStoreLockfileGenerator.generateMarkdownTree(packages: [curl])

        XCTAssertTrue(tree.contains("# Package Dependency Tree"))
        XCTAssertTrue(tree.contains("- **cURL** (`8.5.0`)"))
        XCTAssertTrue(tree.contains("└── openssl@3"))
    }
}
