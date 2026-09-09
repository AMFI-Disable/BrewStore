@testable import BrewStore
import XCTest

final class MoleManagerTests: XCTestCase {
    @MainActor
    func testMoleManagerBinaryDetection() {
        let manager = BrewStoreMoleManager.shared
        manager.detectBinary()

        if let path = manager.binaryPath {
            XCTAssertTrue(manager.isAvailable)
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
        } else {
            XCTAssertFalse(manager.isAvailable)
        }
    }

    func testUninstallModesPropertiesAndCodable() throws {
        let modes = BrewStoreAppUninstallMode.allCases
        XCTAssertEqual(modes.count, 3)

        for mode in modes {
            XCTAssertFalse(mode.id.isEmpty)
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.shortLabel.isEmpty)
            XCTAssertFalse(mode.subtitle.isEmpty)
            XCTAssertFalse(mode.icon.isEmpty)

            // Test JSON Codable
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(BrewStoreAppUninstallMode.self, from: data)
            XCTAssertEqual(mode, decoded)
        }
    }

    @MainActor
    func testBundleOnlyDeletionRejection() {
        let manager = BrewStoreMoleManager.shared
        let invalidURL = URL(fileURLWithPath: "/tmp/not_an_application.txt")

        XCTAssertThrowsError(try manager.deleteBundleOnly(appURL: invalidURL)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "com.amfi-disable.brewstore.mole")
            XCTAssertEqual(nsError.code, 1)
        }
    }

    @MainActor
    func testMoleUninstallInFixtureMode() async {
        let manager = BrewStoreMoleManager.shared
        BrewStoreFixtureMode.setOverrideActive(true)
        defer { BrewStoreFixtureMode.setOverrideActive(false) }

        let result = await manager.uninstallAppWithMole(appName: "TestDummyApp")
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("[Fixture]"))
        XCTAssertEqual(manager.lastOutput, result.output)
    }

    @MainActor
    func testExecuteReplacementInFixtureMode() async {
        BrewStoreFixtureMode.setOverrideActive(true)
        defer { BrewStoreFixtureMode.setOverrideActive(false) }

        let homebrewManager = HomebrewManager()
        let mapping = OpenSourceAlternativeMapping(
            id: "dummy-test-mapping",
            targetProprietaryApp: "DummyApp",
            targetBundleID: "com.dummy.app",
            replacementPackageID: "dummy-replacement",
            replacementName: "Dummy Replacement",
            replacementKind: .formula,
            category: "Testing",
            advantages: ["Advantage 1", "Advantage 2"],
            whyReplace: "Testing replacement pipeline"
        )

        // Test preserveData mode
        let resPreserve = await BrewStoreAppReplacementManager.shared.executeReplacement(
            mapping: mapping,
            mode: .preserveData,
            appURL: URL(fileURLWithPath: "/Applications/DummyApp.app"),
            manager: homebrewManager
        )
        XCTAssertTrue(resPreserve.success)

        // Test purgeAllData mode (Mole)
        let resPurge = await BrewStoreAppReplacementManager.shared.executeReplacement(
            mapping: mapping,
            mode: .purgeAllData,
            appURL: URL(fileURLWithPath: "/Applications/DummyApp.app"),
            manager: homebrewManager
        )
        XCTAssertTrue(resPurge.success)

        // Test keepExisting mode
        let resKeep = await BrewStoreAppReplacementManager.shared.executeReplacement(
            mapping: mapping,
            mode: .keepExisting,
            appURL: URL(fileURLWithPath: "/Applications/DummyApp.app"),
            manager: homebrewManager
        )
        XCTAssertTrue(resKeep.success)
    }

    @MainActor
    func testAppReplacementCatalogSearchAndMatch() {
        let catalog = BrewStoreAppReplacementManager.curatedAlternativeCatalog
        XCTAssertFalse(catalog.isEmpty)

        guard let firstMapping = catalog.first else {
            XCTFail("Catalog should not be empty")
            return
        }

        let scannedApps = [
            ScannedAppItem(
                id: "scanned-1",
                appName: firstMapping.targetProprietaryApp,
                appPath: "/Applications/\(firstMapping.targetProprietaryApp).app",
                bundleID: firstMapping.targetBundleID,
                installedVersion: "1.0",
                matchedCask: nil,
                matchConfidence: .exactBundleID,
                isAlreadyManaged: false
            )
        ]

        let matched = BrewStoreAppReplacementManager.shared.findMatchingScannedApp(
            for: firstMapping,
            in: scannedApps
        )
        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.appName, firstMapping.targetProprietaryApp)
    }

    @MainActor
    func testPreferencesDefaultUninstallModePersistence() {
        let prefs = BrewStorePreferences.shared
        let original = prefs.defaultUninstallMode

        prefs.defaultUninstallMode = .purgeAllData
        XCTAssertEqual(prefs.defaultUninstallMode, .purgeAllData)

        prefs.defaultUninstallMode = .keepExisting
        XCTAssertEqual(prefs.defaultUninstallMode, .keepExisting)

        prefs.defaultUninstallMode = original
    }

    @MainActor
    func testNativeSafePurgeApplicationData() {
        let replacementMgr = BrewStoreAppReplacementManager.shared
        BrewStoreFixtureMode.setOverrideActive(true)
        defer { BrewStoreFixtureMode.setOverrideActive(false) }

        let result = replacementMgr.purgeAllApplicationDataNatively(
            appName: "TestNonExistentApp",
            bundleID: "com.test.nonexistent",
            appURL: nil
        )
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.movedCount, 1)
        XCTAssertTrue(result.errors.isEmpty)
    }
}
