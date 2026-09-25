import XCTest
@testable import BrewStore

@MainActor
final class UpgradeDiffEngineTests: XCTestCase {

    var tempDir: URL!
    var engine: UpgradeDiffEngine!

    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("UpgradeDiffTests_\(uniqueID)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        engine = UpgradeDiffEngine(commandExecutor: .shared)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testSemVerVersionJumpCalculation() {
        XCTAssertEqual(UpgradeDiffEngine.computeVersionJump(from: "1.2.0", to: "2.0.0"), .major)
        XCTAssertEqual(UpgradeDiffEngine.computeVersionJump(from: "1.2.0", to: "1.3.0"), .minor)
        XCTAssertEqual(UpgradeDiffEngine.computeVersionJump(from: "1.2.0", to: "1.2.1"), .patch)
        XCTAssertEqual(UpgradeDiffEngine.computeVersionJump(from: "v1.4.0", to: "v1.5.0"), .minor)
        XCTAssertEqual(UpgradeDiffEngine.computeVersionJump(from: "2.0.0", to: "2.0.0"), .unknown)
        XCTAssertEqual(UpgradeDiffEngine.computeVersionJump(from: "alpha", to: "beta"), .unknown)
    }

    func testLCSDiffComputation() {
        let oldLines = [
            "class Tool < Formula",
            "  version \"1.0.0\"",
            "  depends_on \"dep-a\"",
            "end"
        ]

        let newLines = [
            "class Tool < Formula",
            "  version \"1.1.0\"",
            "  depends_on \"dep-a\"",
            "  depends_on \"dep-b\"",
            "end"
        ]

        let diff = UpgradeDiffEngine.computeDiff(oldLines: oldLines, newLines: newLines)
        XCTAssertFalse(diff.isEmpty)

        let addedLines = diff.filter { $0.type == .added }
        let removedLines = diff.filter { $0.type == .removed }
        let unchangedLines = diff.filter { $0.type == .unchanged }

        // "version \"1.1.0\"" and "depends_on \"dep-b\"" added
        XCTAssertEqual(addedLines.count, 2)
        // "version \"1.0.0\"" removed
        XCTAssertEqual(removedLines.count, 1)
        // "class Tool < Formula", "depends_on \"dep-a\"", "end" unchanged
        XCTAssertEqual(unchangedLines.count, 3)

        XCTAssertTrue(addedLines.contains { $0.content.contains("version \"1.1.0\"") })
        XCTAssertTrue(addedLines.contains { $0.content.contains("depends_on \"dep-b\"") })
        XCTAssertTrue(removedLines.contains { $0.content.contains("version \"1.0.0\"") })
    }

    func testEmptyDiffScenarios() {
        let oldLines = ["line 1", "line 2"]
        let newLines: [String] = []

        let diffRemovedAll = UpgradeDiffEngine.computeDiff(oldLines: oldLines, newLines: newLines)
        XCTAssertEqual(diffRemovedAll.count, 2)
        XCTAssertTrue(diffRemovedAll.allSatisfy { $0.type == .removed })

        let diffAddedAll = UpgradeDiffEngine.computeDiff(oldLines: [], newLines: oldLines)
        XCTAssertEqual(diffAddedAll.count, 2)
        XCTAssertTrue(diffAddedAll.allSatisfy { $0.type == .added })
    }

    func testManifestDiffWithSimulatedCellarPackage() throws {
        let fm = FileManager.default
        let prefixPath = tempDir.path

        // 1. Create Cellar package directory: Cellar/my-tool/1.0.0/
        let versionDir = tempDir.appendingPathComponent("Cellar/my-tool/1.0.0", isDirectory: true)
        let brewDir = versionDir.appendingPathComponent(".brew", isDirectory: true)
        try fm.createDirectory(at: brewDir, withIntermediateDirectories: true)

        let rubyFile = brewDir.appendingPathComponent("my-tool.rb")
        let rubyContent = """
        class MyTool < Formula
          desc "Test tool"
          version "1.0.0"
          depends_on "openssl@1.1"
        end
        """
        try rubyContent.write(to: rubyFile, atomically: true, encoding: .utf8)

        // 2. Create INSTALL_RECEIPT.json
        let receiptFile = versionDir.appendingPathComponent("INSTALL_RECEIPT.json")
        let receiptJSON = """
        {
          "runtime_dependencies": [
            {
              "full_name": "openssl@1.1",
              "version": "1.1.1w"
            }
          ]
        }
        """
        try receiptJSON.write(to: receiptFile, atomically: true, encoding: .utf8)

        let package = BrewStorePackage(
            id: "my-tool",
            name: "my-tool",
            description: "Test tool",
            homepage: "https://example.com",
            version: "1.0.0",
            kind: .formula,
            applicationNames: [],
            isInstalled: true,
            isOutdated: true,
            isPinned: false,
            tap: "homebrew/core",
            dependencies: ["openssl@1.1"],
            dependents: [],
            caveats: nil,
            installedVersion: "1.0.0"
        )

        let manifest = UpgradeDiffEngine.buildDiffManifest(
            package: package,
            prefix: prefixPath,
            fileManager: fm,
            executor: .shared
        )

        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.packageID, "my-tool")
        XCTAssertEqual(manifest?.installedVersion, "1.0.0")
        XCTAssertEqual(manifest?.localManifestPath, rubyFile.path)
        XCTAssertTrue(manifest?.hasDiff ?? false)
    }

    func testDependencyDeltaComputation() {
        let localDeps: Set<String> = ["libgit2", "oniguruma", "dep-deprecated"]
        let remoteDeps: Set<String> = ["libgit2", "oniguruma", "openssl@3", "rust"]

        let added = Array(remoteDeps.subtracting(localDeps)).sorted()
        let removed = Array(localDeps.subtracting(remoteDeps)).sorted()
        let unchanged = Array(localDeps.intersection(remoteDeps)).sorted()

        let delta = DependencyDelta(added: added, removed: removed, unchanged: unchanged)

        XCTAssertTrue(delta.hasChanges)
        XCTAssertEqual(delta.added, ["openssl@3", "rust"])
        XCTAssertEqual(delta.removed, ["dep-deprecated"])
        XCTAssertEqual(delta.unchanged, ["libgit2", "oniguruma"])
    }
}
