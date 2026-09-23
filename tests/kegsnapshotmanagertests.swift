import XCTest
@testable import BrewStore

@MainActor
final class KegSnapshotManagerTests: XCTestCase {

    var tempDir: URL!
    var tempPrefix: String!
    var manager: KegSnapshotManager!

    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BrewStoreKegTests_\(uniqueID)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempPrefix = tempDir.path
        manager = KegSnapshotManager(commandExecutor: .shared)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testDirectoryPathResolvers() {
        let cellar = manager.cellarDirectory(for: "testpkg", prefix: tempPrefix)
        XCTAssertEqual(cellar.path, "\(tempPrefix!)/Cellar/testpkg")

        let linked = manager.linkedKegRecord(for: "testpkg", prefix: tempPrefix)
        XCTAssertEqual(linked.path, "\(tempPrefix!)/var/homebrew/linked/testpkg")

        let opt = manager.optDirectory(for: "testpkg", prefix: tempPrefix)
        XCTAssertEqual(opt.path, "\(tempPrefix!)/opt/testpkg")

        let bin = manager.binDirectory(prefix: tempPrefix)
        XCTAssertEqual(bin.path, "\(tempPrefix!)/bin")
    }

    func testScanPackageKegsDetectsInstalledAndActive() throws {
        let fm = FileManager.default
        let pkgCellar = manager.cellarDirectory(for: "sampleapp", prefix: tempPrefix)
        let v1 = pkgCellar.appendingPathComponent("1.0.0")
        let v2 = pkgCellar.appendingPathComponent("2.1.0")

        try fm.createDirectory(at: v1, withIntermediateDirectories: true)
        try fm.createDirectory(at: v2, withIntermediateDirectories: true)

        // Mock linked symlink pointing to v2
        let linkedURL = manager.linkedKegRecord(for: "sampleapp", prefix: tempPrefix)
        try fm.createDirectory(at: linkedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: linkedURL.path, withDestinationPath: "../../../Cellar/sampleapp/2.1.0")

        let state = manager.scanPackageKegs(for: "sampleapp", prefix: tempPrefix)

        XCTAssertEqual(state.packageID, "sampleapp")
        XCTAssertEqual(state.activeLinkedVersion, "2.1.0")
        XCTAssertEqual(state.installedVersions.count, 2)

        let v2Entry = state.installedVersions.first { $0.version == "2.1.0" }
        XCTAssertNotNil(v2Entry)
        XCTAssertTrue(v2Entry?.isCurrentlyLinked == true)

        let v1Entry = state.installedVersions.first { $0.version == "1.0.0" }
        XCTAssertNotNil(v1Entry)
        XCTAssertFalse(v1Entry?.isCurrentlyLinked == true)
    }

    func testCreateSnapshotAndRestore() async throws {
        let fm = FileManager.default
        let pkgCellar = manager.cellarDirectory(for: "archiveapp", prefix: tempPrefix)
        let v1 = pkgCellar.appendingPathComponent("1.0.0")
        try fm.createDirectory(at: v1, withIntermediateDirectories: true)

        let testFile = v1.appendingPathComponent("binary.txt")
        try "hello snapshot".write(to: testFile, atomically: true, encoding: .utf8)

        // Create snapshot
        let snapshot = try await manager.createSnapshot(packageID: "archiveapp", version: "1.0.0", prefix: tempPrefix)
        XCTAssertEqual(snapshot.packageID, "archiveapp")
        XCTAssertEqual(snapshot.version, "1.0.0")
        XCTAssertTrue(fm.fileExists(atPath: snapshot.filePath))
        XCTAssertGreaterThan(snapshot.sizeBytes, 0)

        // Delete v1 from cellar
        try fm.removeItem(at: v1)
        XCTAssertFalse(fm.fileExists(atPath: v1.path))

        // Restore snapshot
        try await manager.restoreSnapshot(archive: snapshot, prefix: tempPrefix)
        XCTAssertTrue(fm.fileExists(atPath: v1.path))
        XCTAssertTrue(fm.fileExists(atPath: testFile.path))

        let content = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(content, "hello snapshot")

        // Cleanup snapshot
        try manager.deleteSnapshot(archive: snapshot, prefix: tempPrefix)
        XCTAssertFalse(fm.fileExists(atPath: snapshot.filePath))
    }

    func testRollbackSymlinkAtomicRepoint() async throws {
        let fm = FileManager.default
        let pkgCellar = manager.cellarDirectory(for: "rollbackapp", prefix: tempPrefix)
        let v1 = pkgCellar.appendingPathComponent("1.0.0")
        let v2 = pkgCellar.appendingPathComponent("2.0.0")

        let v1Bin = v1.appendingPathComponent("bin")
        let v2Bin = v2.appendingPathComponent("bin")
        try fm.createDirectory(at: v1Bin, withIntermediateDirectories: true)
        try fm.createDirectory(at: v2Bin, withIntermediateDirectories: true)

        let binFile1 = v1Bin.appendingPathComponent("appcmd")
        let binFile2 = v2Bin.appendingPathComponent("appcmd")
        try "v1".write(to: binFile1, atomically: true, encoding: .utf8)
        try "v2".write(to: binFile2, atomically: true, encoding: .utf8)

        let globalBin = manager.binDirectory(prefix: tempPrefix)
        try fm.createDirectory(at: globalBin, withIntermediateDirectories: true)

        // Initial state: link v2
        let optURL = manager.optDirectory(for: "rollbackapp", prefix: tempPrefix)
        try fm.createDirectory(at: optURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: optURL.path, withDestinationPath: "../Cellar/rollbackapp/2.0.0")

        let linkedURL = manager.linkedKegRecord(for: "rollbackapp", prefix: tempPrefix)
        try fm.createDirectory(at: linkedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: linkedURL.path, withDestinationPath: "../../../Cellar/rollbackapp/2.0.0")

        let activeBefore = manager.detectActiveVersion(for: "rollbackapp", prefix: tempPrefix)
        XCTAssertEqual(activeBefore, "2.0.0")

        // Execute Rollback to v1.0.0
        try await manager.rollback(packageID: "rollbackapp", to: "1.0.0", prefix: tempPrefix)

        let activeAfter = manager.detectActiveVersion(for: "rollbackapp", prefix: tempPrefix)
        XCTAssertEqual(activeAfter, "1.0.0")

        let globalSymlink = globalBin.appendingPathComponent("appcmd")
        XCTAssertTrue(fm.fileExists(atPath: globalSymlink.path))
        let binContent = try String(contentsOf: globalSymlink, encoding: .utf8)
        XCTAssertEqual(binContent, "v1")
    }
}
