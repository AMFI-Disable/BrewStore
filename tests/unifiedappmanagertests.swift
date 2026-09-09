@testable import BrewStore
import XCTest

@MainActor
final class UnifiedAppManagerTests: XCTestCase {
    func testAppSourcePreferencePropertiesAndCodable() throws {
        let prefs = AppSourcePreference.allCases
        XCTAssertEqual(prefs.count, 2)

        for pref in prefs {
            XCTAssertFalse(pref.id.isEmpty)
            XCTAssertFalse(pref.title.isEmpty)
            XCTAssertFalse(pref.shortLabel.isEmpty)
            XCTAssertFalse(pref.subtitle.isEmpty)

            let data = try JSONEncoder().encode(pref)
            let decoded = try JSONDecoder().decode(AppSourcePreference.self, from: data)
            XCTAssertEqual(pref, decoded)
        }

        XCTAssertTrue(AppSourcePreference.homebrew.title.contains("Recommended"))
    }

    func testAppSourceProperties() {
        let sources = AppSource.allCases
        XCTAssertEqual(sources.count, 4)

        for source in sources {
            XCTAssertFalse(source.id.isEmpty)
            XCTAssertFalse(source.displayName.isEmpty)
            XCTAssertFalse(source.icon.isEmpty)
        }
    }

    func testPreferencesDefaultAppSourcePreferencePersistence() {
        let preferences = BrewStorePreferences.shared
        let original = preferences.defaultAppSourcePreference

        preferences.defaultAppSourcePreference = .macAppStore
        XCTAssertEqual(preferences.defaultAppSourcePreference, .macAppStore)

        preferences.defaultAppSourcePreference = .homebrew
        XCTAssertEqual(preferences.defaultAppSourcePreference, .homebrew)

        preferences.resetToDefaults()
        XCTAssertEqual(preferences.defaultAppSourcePreference, .homebrew)

        preferences.defaultAppSourcePreference = original
    }

    func testScannedAppItemDualAvailability() {
        let dummyCask = BrewStorePackage(
            id: "slack",
            name: "Slack",
            description: "Messaging app",
            homepage: "https://slack.com",
            version: "4.38.0",
            kind: .cask
        )

        let masItem = ScannedAppItem(
            id: "/Applications/Slack.app",
            appName: "Slack",
            appPath: "/Applications/Slack.app",
            bundleID: "com.tinyspeck.slackmacgap",
            installedVersion: "4.38.0",
            matchedCask: dummyCask,
            matchConfidence: .exactVerified,
            isAlreadyManaged: false,
            requiresManualReview: false,
            reviewReasons: [],
            isFromMacAppStore: true,
            masAppID: "803453959"
        )

        XCTAssertTrue(masItem.isFromMacAppStore)
        XCTAssertTrue(masItem.isDualAvailable)

        let standaloneItem = ScannedAppItem(
            id: "/Applications/Custom.app",
            appName: "Custom",
            appPath: "/Applications/Custom.app",
            bundleID: "com.custom.app",
            installedVersion: "1.0.0",
            matchedCask: nil,
            matchConfidence: .unmatched,
            isAlreadyManaged: false,
            isFromMacAppStore: false
        )

        XCTAssertFalse(standaloneItem.isFromMacAppStore)
        XCTAssertFalse(standaloneItem.isDualAvailable)
    }

    func testUnifiedInventoryRebuild() {
        let manager = HomebrewManager()
        let unifiedMgr = BrewStoreUnifiedAppManager.shared

        let caskPkg = BrewStorePackage(
            id: "test-cask",
            name: "Test Cask",
            description: "Test",
            homepage: "",
            version: "1.1.0",
            kind: .cask,
            isInstalled: true,
            isOutdated: true,
            installedVersion: "1.0.0"
        )
        let formulaPkg = BrewStorePackage(
            id: "test-formula",
            name: "Test Formula",
            description: "Test",
            homepage: "",
            version: "2.0.0",
            kind: .formula,
            isInstalled: true
        )

        manager.packages = [caskPkg, formulaPkg]

        unifiedMgr.rebuildInventory(homebrewManager: manager)

        XCTAssertTrue(unifiedMgr.casks.contains { $0.id == "cask-test-cask" })
        XCTAssertTrue(unifiedMgr.formulae.contains { $0.id == "formula-test-formula" })
        XCTAssertTrue(unifiedMgr.outdatedApps.contains { $0.id == "cask-test-cask" })
        XCTAssertEqual(unifiedMgr.outdatedApps.first(where: { $0.id == "cask-test-cask" })?.displayVersion, "1.0.0 → 1.1.0")
    }
}
