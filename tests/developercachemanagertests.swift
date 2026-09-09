@testable import BrewStore
import XCTest

@MainActor
final class DeveloperCacheManagerTests: XCTestCase {
    func testDeveloperCacheCategories() {
        let categories = DeveloperCacheCategory.allCases
        XCTAssertEqual(categories.count, 5)

        for cat in categories {
            XCTAssertFalse(cat.id.isEmpty)
            XCTAssertFalse(cat.rawValue.isEmpty)
            XCTAssertFalse(cat.icon.isEmpty)
        }
    }

    func testDeveloperCacheTargetProperties() {
        let target = DeveloperCacheTarget(
            id: "test-target",
            name: "Test Cache",
            category: .xcode,
            description: "Test description",
            url: URL(fileURLWithPath: "/tmp/test"),
            sizeBytes: 1024 * 1024 * 50,
            isSelected: true
        )

        XCTAssertEqual(target.id, "test-target")
        XCTAssertEqual(target.name, "Test Cache")
        XCTAssertEqual(target.category, .xcode)
        XCTAssertEqual(target.description, "Test description")
        XCTAssertEqual(target.sizeBytes, 52428800)
        XCTAssertTrue(target.isSelected)
        XCTAssertFalse(target.formattedSize.isEmpty)
    }

    func testSelectionAndReclaimableCalculations() {
        let manager = BrewStoreDeveloperCacheManager.shared

        let t1 = DeveloperCacheTarget(
            id: "target-1",
            name: "Target 1",
            category: .xcode,
            description: "Target 1 Desc",
            url: URL(fileURLWithPath: "/tmp/t1"),
            sizeBytes: 100 * 1024 * 1024,
            isSelected: true
        )

        let t2 = DeveloperCacheTarget(
            id: "target-2",
            name: "Target 2",
            category: .docker,
            description: "Target 2 Desc",
            url: URL(fileURLWithPath: "/tmp/t2"),
            sizeBytes: 200 * 1024 * 1024,
            isSelected: false
        )

        manager.targets = [t1, t2]

        XCTAssertEqual(manager.totalReclaimableBytes, 300 * 1024 * 1024)
        XCTAssertEqual(manager.selectedReclaimableBytes, 100 * 1024 * 1024)
        XCTAssertFalse(manager.formattedTotalReclaimable.isEmpty)
        XCTAssertFalse(manager.formattedSelectedReclaimable.isEmpty)

        // Toggle t2 on
        manager.toggleTarget(id: "target-2")
        XCTAssertEqual(manager.selectedReclaimableBytes, 300 * 1024 * 1024)

        // Deselect all
        manager.deselectAll()
        XCTAssertEqual(manager.selectedReclaimableBytes, 0)
        for target in manager.targets {
            XCTAssertFalse(target.isSelected)
        }

        // Select all
        manager.selectAll()
        XCTAssertEqual(manager.selectedReclaimableBytes, 300 * 1024 * 1024)
        for target in manager.targets {
            XCTAssertTrue(target.isSelected)
        }
    }

    func testComputeDirectorySize() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("devcache_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileA = tempDir.appendingPathComponent("fileA.bin")
        let fileB = tempDir.appendingPathComponent("fileB.bin")
        let dataA = Data(repeating: 0x1, count: 2048)
        let dataB = Data(repeating: 0x2, count: 4096)

        try dataA.write(to: fileA)
        try dataB.write(to: fileB)

        let size = BrewStoreDeveloperCacheManager.computeDirectorySize(url: tempDir)
        XCTAssertEqual(size, 6144)

        let nonexistent = URL(fileURLWithPath: "/path/to/definitely/nonexistent/\(UUID().uuidString)")
        let nonSize = BrewStoreDeveloperCacheManager.computeDirectorySize(url: nonexistent)
        XCTAssertEqual(nonSize, 0)
    }

    func testPurgeSelectedWhenEmptyDoesNotHangOrChangeState() {
        let manager = BrewStoreDeveloperCacheManager.shared
        manager.deselectAll()
        XCTAssertFalse(manager.isPurging)

        manager.purgeSelected()
        XCTAssertFalse(manager.isPurging)
    }
}
