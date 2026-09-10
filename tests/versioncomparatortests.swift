@testable import BrewStore
import XCTest

final class VersionComparatorTests: XCTestCase {
    func testMajorVersionUpgradeDetection() {
        XCTAssertTrue(BrewStoreVersionComparator.isMajorUpgrade(installed: "15.4.1", latest: "16.0.0"))
        XCTAssertTrue(BrewStoreVersionComparator.isMajorUpgrade(installed: "v20.10.0", latest: "v22.1.0"))
        XCTAssertTrue(BrewStoreVersionComparator.isMajorUpgrade(installed: "2.8", latest: "3.0"))
    }

    func testMinorAndPatchUpdatesNotMajor() {
        XCTAssertFalse(BrewStoreVersionComparator.isMajorUpgrade(installed: "16.1.0", latest: "16.2.0"))
        XCTAssertFalse(BrewStoreVersionComparator.isMajorUpgrade(installed: "16.1.0", latest: "16.1.1"))
        XCTAssertFalse(BrewStoreVersionComparator.isMajorUpgrade(installed: "16.0", latest: "16.0"))
    }

    func testDowngradeNotMajorUpgrade() {
        XCTAssertFalse(BrewStoreVersionComparator.isMajorUpgrade(installed: "17.0", latest: "16.0"))
    }

    func testSummaryFormatting() {
        let summary = BrewStoreVersionComparator.majorUpgradeSummary(installed: "15.2", latest: "16.0.1")
        XCTAssertEqual(summary, "v15 → v16")

        let noSummary = BrewStoreVersionComparator.majorUpgradeSummary(installed: "15.2", latest: "15.3")
        XCTAssertNil(noSummary)
    }

    func testMalformedVersionsHandledGracefully() {
        XCTAssertFalse(BrewStoreVersionComparator.isMajorUpgrade(installed: nil, latest: "1.0"))
        XCTAssertFalse(BrewStoreVersionComparator.isMajorUpgrade(installed: "1.0", latest: nil))
        XCTAssertFalse(BrewStoreVersionComparator.isMajorUpgrade(installed: "abc", latest: "def"))
    }
}
