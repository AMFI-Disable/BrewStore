@testable import BrewStore
import XCTest

@MainActor
final class AppStorageInspectorTests: XCTestCase {
    func testAppStorageBreakdownCalculations() {
        let breakdown = AppStorageBreakdown(
            binaryBytes: 200 * 1024 * 1024,
            cacheBytes: 500 * 1024 * 1024,
            dataBytes: 300 * 1024 * 1024,
            cacheCandidates: [],
            dataCandidates: []
        )

        XCTAssertEqual(breakdown.totalBytes, 1000 * 1024 * 1024)
        XCTAssertFalse(breakdown.formattedBinary.isEmpty)
        XCTAssertFalse(breakdown.formattedCache.isEmpty)
        XCTAssertFalse(breakdown.formattedData.isEmpty)
        XCTAssertFalse(breakdown.formattedTotal.isEmpty)
    }

    func testComputeDirectorySizeForTempFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("test.dat")
        let testData = Data(repeating: 0x42, count: 1024)
        try testData.write(to: testFile)

        let size = BrewStoreAppStorageInspector.computeDirectorySize(url: tempDir)
        XCTAssertEqual(size, 1024)
    }

    func testCalculateBreakdownWithMockPackage() {
        let pkg = BrewStorePackage(
            id: "test-cask",
            name: "TestApp",
            description: "Mock cask for storage testing",
            homepage: "",
            version: "1.0",
            kind: .cask,
            isInstalled: false
        )

        let breakdown = BrewStoreAppStorageInspector.calculateBreakdown(
            package: pkg,
            appURL: nil,
            bundleID: "",
            appName: "TestApp"
        )

        XCTAssertEqual(breakdown.binaryBytes, 0)
        XCTAssertEqual(breakdown.cacheBytes, 0)
        XCTAssertEqual(breakdown.dataBytes, 0)
        XCTAssertEqual(breakdown.totalBytes, 0)
    }

    func testCandidateSelectionToggles() {
        let inspector = BrewStoreAppStorageInspector()
        let c1 = BrewStoreRemovalCandidate(
            url: URL(fileURLWithPath: "/tmp/c1"),
            kind: .cache,
            size: 1024,
            confidence: .relatedPath,
            isSelected: true
        )
        let c2 = BrewStoreRemovalCandidate(
            url: URL(fileURLWithPath: "/tmp/c2"),
            kind: .cache,
            size: 2048,
            confidence: .relatedPath,
            isSelected: true
        )

        inspector.breakdown = AppStorageBreakdown(
            binaryBytes: 0,
            cacheBytes: 3072,
            dataBytes: 0,
            cacheCandidates: [c1, c2],
            dataCandidates: []
        )

        // Toggle c1 off
        inspector.toggleCandidateSelection(url: c1.url)
        XCTAssertEqual(inspector.breakdown?.cacheCandidates.first(where: { $0.url == c1.url })?.isSelected, false)
        XCTAssertEqual(inspector.breakdown?.cacheCandidates.first(where: { $0.url == c2.url })?.isSelected, true)

        // Deselect all
        inspector.deselectAllCandidates()
        for candidate in inspector.breakdown?.cacheCandidates ?? [] {
            XCTAssertFalse(candidate.isSelected)
        }

        // Select all
        inspector.selectAllCandidates()
        for candidate in inspector.breakdown?.cacheCandidates ?? [] {
            XCTAssertTrue(candidate.isSelected)
        }
    }

    func testCleanSelectedCachesNoCrashWhenEmpty() {
        let inspector = BrewStoreAppStorageInspector()
        let pkg = BrewStorePackage(
            id: "test",
            name: "Test",
            description: "",
            homepage: "",
            version: "1.0",
            kind: .formula,
            isInstalled: true
        )

        inspector.cleanSelectedCaches(package: pkg)
        XCTAssertFalse(inspector.isCleaning)
    }
}
