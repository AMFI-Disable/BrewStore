@testable import BrewStore
import XCTest

@MainActor
final class AppAdoptionPrecisionTests: XCTestCase {
    private func makeCask(
        id: String,
        name: String,
        version: String,
        appNames: [String] = []
    ) -> BrewStorePackage {
        BrewStorePackage(
            id: id,
            name: name,
            description: "Test cask for \(id)",
            homepage: "https://example.com/\(id)",
            version: version,
            kind: .cask,
            applicationNames: appNames
        )
    }

    func testFirefox154DoesNotExactMatchFirefoxCN116() {
        let firefoxCN = makeCask(id: "firefox@cn", name: "Firefox", version: "116.0", appNames: ["Firefox.app"])
        let casks = [firefoxCN]

        let result = BrewStoreAppAdoptionManager.matchCask(
            appName: "Firefox",
            fileName: "Firefox",
            bundleID: "org.mozilla.firefox",
            installedVersion: "154.0",
            casks: casks
        )

        // Must NOT be classified as verified exact
        XCTAssertNotEqual(result.confidence, .exactVerified)
        XCTAssertNotEqual(result.confidence, .exactBundleID)
        XCTAssertNotEqual(result.confidence, .exactName)
        XCTAssertTrue(result.requiresReview)
        XCTAssertFalse(result.reviewReasons.isEmpty)

        let scannedItem = ScannedAppItem(
            id: "/Applications/Firefox.app",
            appName: "Firefox",
            appPath: "/Applications/Firefox.app",
            bundleID: "org.mozilla.firefox",
            installedVersion: "154.0",
            matchedCask: result.cask,
            matchConfidence: result.confidence,
            isAlreadyManaged: false,
            requiresManualReview: result.requiresReview,
            reviewReasons: result.reviewReasons
        )

        // Must NOT be adoptable
        XCTAssertFalse(scannedItem.isAdoptable)
    }

    func testPrefersCanonicalFirefoxWhenBothPresent() {
        let firefoxCN = makeCask(id: "firefox@cn", name: "Firefox", version: "116.0", appNames: ["Firefox.app"])
        let firefoxCanonical = makeCask(id: "firefox", name: "Firefox", version: "154.0", appNames: ["Firefox.app"])
        let casks = [firefoxCN, firefoxCanonical]

        let result = BrewStoreAppAdoptionManager.matchCask(
            appName: "Firefox",
            fileName: "Firefox",
            bundleID: "org.mozilla.firefox",
            installedVersion: "154.0",
            casks: casks
        )

        XCTAssertEqual(result.cask?.id, "firefox")
        XCTAssertFalse(result.requiresReview)
        XCTAssertTrue(result.confidence.isVerifiedSafe)

        let scannedItem = ScannedAppItem(
            id: "/Applications/Firefox.app",
            appName: "Firefox",
            appPath: "/Applications/Firefox.app",
            bundleID: "org.mozilla.firefox",
            installedVersion: "154.0",
            matchedCask: result.cask,
            matchConfidence: result.confidence,
            isAlreadyManaged: false,
            requiresManualReview: result.requiresReview,
            reviewReasons: result.reviewReasons
        )

        XCTAssertTrue(scannedItem.isAdoptable)
    }

    func testVersionDiscrepancyFlagsReview() {
        let appCask = makeCask(id: "legacy-tool", name: "Legacy Tool", version: "2.0.0", appNames: ["Legacy Tool.app"])
        let casks = [appCask]

        let result = BrewStoreAppAdoptionManager.matchCask(
            appName: "Legacy Tool",
            fileName: "Legacy Tool",
            bundleID: "com.example.legacytool",
            installedVersion: "12.0.0",
            casks: casks
        )

        XCTAssertTrue(result.requiresReview)
        XCTAssertEqual(result.confidence, .versionMismatch)
        XCTAssertTrue(result.reviewReasons.contains { $0.contains("version") })
    }

    func testAdoptAllExcludesUncertainAndReviewFlaggedItems() {
        let adoptionManager = BrewStoreAppAdoptionManager()

        let verifiedItem = ScannedAppItem(
            id: "/Applications/VLC.app",
            appName: "VLC",
            appPath: "/Applications/VLC.app",
            bundleID: "org.videolan.vlc",
            installedVersion: "3.0.20",
            matchedCask: makeCask(id: "vlc", name: "VLC", version: "3.0.20"),
            matchConfidence: .exactBundleID,
            isAlreadyManaged: false,
            requiresManualReview: false,
            reviewReasons: []
        )

        let uncertainItem = ScannedAppItem(
            id: "/Applications/Firefox.app",
            appName: "Firefox",
            appPath: "/Applications/Firefox.app",
            bundleID: "org.mozilla.firefox",
            installedVersion: "154.0",
            matchedCask: makeCask(id: "firefox@cn", name: "Firefox", version: "116.0"),
            matchConfidence: .channelMismatch,
            isAlreadyManaged: false,
            requiresManualReview: true,
            reviewReasons: ["Locale/Channel mismatch: app has no channel while cask specifies @cn."]
        )

        XCTAssertTrue(verifiedItem.isAdoptable)
        XCTAssertFalse(uncertainItem.isAdoptable)

        adoptionManager.scannedApps = [verifiedItem, uncertainItem]
        XCTAssertEqual(adoptionManager.adoptableApps.count, 1)
        XCTAssertEqual(adoptionManager.adoptableApps.first?.id, "/Applications/VLC.app")
        XCTAssertEqual(adoptionManager.reviewRequiredApps.count, 1)
        XCTAssertEqual(adoptionManager.reviewRequiredApps.first?.id, "/Applications/Firefox.app")
    }
}
