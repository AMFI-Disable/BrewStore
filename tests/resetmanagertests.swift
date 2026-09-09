@testable import BrewStore
import XCTest

final class ResetManagerTests: XCTestCase {
    @MainActor
    func testResetTiersAndOptions() {
        XCTAssertEqual(BrewStoreResetTier.allCases.count, 4)
        XCTAssertEqual(BrewStoreResetOption.allCases.count, 8)

        // Verify tier memberships
        XCTAssertEqual(BrewStoreResetOption.unpinEverything.tier, .safe)
        XCTAssertEqual(BrewStoreResetOption.unstarEverything.tier, .safe)

        XCTAssertEqual(BrewStoreResetOption.clearPersonalSettings.tier, .caution)
        XCTAssertEqual(BrewStoreResetOption.resetEverythingForApp.tier, .caution)

        XCTAssertEqual(BrewStoreResetOption.cleanupEverything.tier, .danger)
        XCTAssertEqual(BrewStoreResetOption.unlinkEverything.tier, .danger)
        XCTAssertEqual(BrewStoreResetOption.untapEverything.tier, .danger)

        XCTAssertEqual(BrewStoreResetOption.uninstallEverything.tier, .dangerDanger)
    }

    @MainActor
    func testNuclearVerificationPhraseAccuracy() {
        let manager = BrewStoreResetManager.shared

        XCTAssertTrue(manager.verifyNuclearPhrase("UNINSTALL ALL PACKAGES"))
        XCTAssertTrue(manager.verifyNuclearPhrase("  UNINSTALL ALL PACKAGES  \n"))

        // Case-sensitive exact match required
        XCTAssertFalse(manager.verifyNuclearPhrase("uninstall all packages"))
        XCTAssertFalse(manager.verifyNuclearPhrase("Uninstall All Packages"))
        XCTAssertFalse(manager.verifyNuclearPhrase("UNINSTALL"))
        XCTAssertFalse(manager.verifyNuclearPhrase("YES"))
        XCTAssertFalse(manager.verifyNuclearPhrase(""))
    }

    @MainActor
    func testSafeActionsExecution() {
        let resetManager = BrewStoreResetManager.shared
        let manager = HomebrewManager()

        // Unstar
        BrewStoreWishlistManager.shared.wishlistIDs.insert("ripgrep")
        XCTAssertTrue(BrewStoreWishlistManager.shared.isWishlisted(id: "ripgrep"))
        resetManager.unstarEverything()
        XCTAssertFalse(BrewStoreWishlistManager.shared.isWishlisted(id: "ripgrep"))
        XCTAssertEqual(resetManager.lastResetMessage, "Cleared all wishlist stars and collections.")

        // Unpin
        resetManager.unpinEverything(manager: manager)
        XCTAssertEqual(resetManager.lastResetMessage, "Unpinned all package version locks.")
    }

    @MainActor
    func testCautionActionsExecution() {
        let resetManager = BrewStoreResetManager.shared
        let manager = HomebrewManager()
        let discovery = BrewStoreDiscoveryCatalog()

        BrewStorePreferences.shared.autoRefreshIntervalSeconds = 120
        resetManager.clearPersonalSettings()
        XCTAssertEqual(BrewStorePreferences.shared.autoRefreshIntervalSeconds, 15)
        XCTAssertEqual(resetManager.lastResetMessage, "Personal settings and interface preferences restored to defaults.")

        resetManager.resetEverythingForApp(manager: manager, discovery: discovery)
        XCTAssertNotNil(resetManager.lastResetMessage)
        XCTAssertTrue(GitServiceManager.shared.accounts.isEmpty)
    }

    @MainActor
    func testDangerZoneNoOpSafety() {
        let resetManager = BrewStoreResetManager.shared
        let manager = HomebrewManager()
        manager.packages = []
        manager.taps = []

        // When no packages installed, unlink should report gracefully
        resetManager.unlinkEverything(manager: manager)
        XCTAssertEqual(resetManager.lastResetMessage, "No installed formulae found to unlink.")

        // When no third-party taps exist, untap should report gracefully
        resetManager.untapEverything(manager: manager)
        XCTAssertEqual(resetManager.lastResetMessage, "No third-party custom taps found to untap.")

        // When no packages installed, nuclear uninstall should report gracefully
        resetManager.uninstallEverything(manager: manager)
        XCTAssertEqual(resetManager.lastResetMessage, "No installed packages found on this Mac.")
    }
}
