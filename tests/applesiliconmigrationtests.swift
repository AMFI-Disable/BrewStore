@testable import BrewStore
import XCTest

@MainActor
final class AppleSiliconMigrationTests: XCTestCase {
    func testAppleSiliconMigrationReportOptimizationStatus() {
        let pkg1 = BrewStorePackage(
            id: "iterm2",
            name: "iTerm2",
            description: "Terminal emulator",
            homepage: "https://iterm2.com",
            version: "3.5.0",
            kind: .cask
        )

        let candidateNative = MigrationCandidate(
            package: pkg1,
            architecture: .appleSilicon,
            binaryPath: "/Applications/iTerm.app",
            needsMigration: false
        )

        let candidateRosetta = MigrationCandidate(
            package: pkg1,
            architecture: .intel,
            binaryPath: "/Applications/iTerm.app",
            needsMigration: true
        )

        let reportOptimized = AppleSiliconMigrationReport(
            isAppleSiliconHost: true,
            totalChecked: 1,
            nativeArm64Count: 1,
            universalCount: 0,
            rosettaIntelCount: 0,
            candidates: [candidateNative]
        )

        XCTAssertTrue(reportOptimized.isFullyOptimized)
        XCTAssertEqual(reportOptimized.migrationRequiredCandidates.count, 0)

        let reportNeedsMigration = AppleSiliconMigrationReport(
            isAppleSiliconHost: true,
            totalChecked: 1,
            nativeArm64Count: 0,
            universalCount: 0,
            rosettaIntelCount: 1,
            candidates: [candidateRosetta]
        )

        XCTAssertFalse(reportNeedsMigration.isFullyOptimized)
        XCTAssertEqual(reportNeedsMigration.migrationRequiredCandidates.count, 1)
        XCTAssertEqual(reportNeedsMigration.migrationRequiredCandidates.first?.package.id, "iterm2")
    }

    func testArchitectureMapLookup() {
        let manager = BrewStoreAppleSiliconMigrationManager.shared
        manager.architectureMap["wget"] = .appleSilicon
        manager.architectureMap["old-intel-cli"] = .intel

        XCTAssertEqual(manager.architecture(for: "wget"), .appleSilicon)
        XCTAssertEqual(manager.architecture(for: "old-intel-cli"), .intel)
        XCTAssertNil(manager.architecture(for: "unknown-package"))
    }

    func testFindFormulaBinaryPathInVersionedCellar() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let versionDir = tempDir.appendingPathComponent("1.2.3")
        let binDir = versionDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let execURL = binDir.appendingPathComponent("customcli")
        FileManager.default.createFile(atPath: execURL.path, contents: Data("#!/bin/sh\necho hi\n".utf8))

        let found = BrewStoreSecurityInspector.findFormulaBinaryPath(
            id: "customcli",
            name: "customcli",
            cellarURL: tempDir
        )

        XCTAssertEqual(found, execURL.path)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }
}
