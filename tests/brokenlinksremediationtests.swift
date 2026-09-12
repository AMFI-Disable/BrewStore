@testable import BrewStore
import XCTest

@MainActor
final class BrokenLinksRemediationTests: XCTestCase {
    func testDanglingSymlinkScanningAndPruning() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let binDir = tempDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Create a valid symlink
        let validTarget = tempDir.appendingPathComponent("valid_target.txt")
        try "content".write(to: validTarget, atomically: true, encoding: .utf8)
        let validLink = binDir.appendingPathComponent("valid_link")
        try FileManager.default.createSymbolicLink(at: validLink, withDestinationURL: validTarget)

        // 2. Create a dangling symlink (pointing to non-existent file)
        let missingTarget = tempDir.appendingPathComponent("missing_target.txt")
        let brokenLink = binDir.appendingPathComponent("broken_link")
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: missingTarget)

        let manager = BrewStoreDoctorRemediationManager.shared
        let dangling = manager.scanDanglingSymlinks(prefixPath: tempDir.path)

        XCTAssertEqual(dangling.count, 1)
        XCTAssertEqual(dangling.first?.lastPathComponent, "broken_link")

        // Prune the broken link
        let result = manager.pruneBrokenSymlinks(links: dangling)
        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: brokenLink.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: validLink.path))
    }

    func testDoctorManagerPrunesBrokenSymlinks() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let binDir = tempDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let missingTarget = tempDir.appendingPathComponent("nonexistent.txt")
        let brokenLink = binDir.appendingPathComponent("orphan_tool")
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: missingTarget)

        let homebrewManager = HomebrewManager()

        BrewStoreDependencyDoctorManager.shared.pruneDanglingSymlinks(manager: homebrewManager, prefixPath: tempDir.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: brokenLink.path))
    }
}
