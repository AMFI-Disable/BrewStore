@testable import BrewStore
import XCTest

final class SidebarNavigationTests: XCTestCase {
    func testAllSidebarSectionsAreValidAndUnique() {
        let allSections = BrewStoreSection.allCases
        XCTAssertEqual(allSections.count, 18)

        var seenIDs = Set<String>()
        for section in allSections {
            XCTAssertFalse(seenIDs.contains(section.id), "Duplicate section id: \(section.id)")
            seenIDs.insert(section.id)
            XCTAssertFalse(section.rawValue.isEmpty)
            XCTAssertFalse(section.icon.isEmpty)
        }
    }

    func testSidebarSectionCategorization() {
        // Storefront sections
        XCTAssertEqual(BrewStoreSection.discover.rawValue, "Discover")
        XCTAssertEqual(BrewStoreSection.showdown.rawValue, "Community Picks")
        XCTAssertEqual(BrewStoreSection.allApps.rawValue, "All Applications")
        XCTAssertEqual(BrewStoreSection.allFormulae.rawValue, "All CLI Tools")
        XCTAssertEqual(BrewStoreSection.stories.rawValue, "Stories")
        XCTAssertEqual(BrewStoreSection.toolkits.rawValue, "Toolkits")
        XCTAssertEqual(BrewStoreSection.categories.rawValue, "Categories")

        // Library sections
        XCTAssertEqual(BrewStoreSection.installed.rawValue, "Installed")
        XCTAssertEqual(BrewStoreSection.adoption.rawValue, "Adoption & Replacements")
        XCTAssertEqual(BrewStoreSection.topology.rawValue, "Dependencies")
        XCTAssertEqual(BrewStoreSection.wishlist.rawValue, "Wishlist")
        XCTAssertEqual(BrewStoreSection.workspaces.rawValue, "Workspaces")
        XCTAssertEqual(BrewStoreSection.services.rawValue, "Services")
        XCTAssertEqual(BrewStoreSection.taps.rawValue, "Taps")

        // Creator & System sections
        XCTAssertEqual(BrewStoreSection.creator.rawValue, "Creator Studio")
        XCTAssertEqual(BrewStoreSection.updates.rawValue, "Updates")
        XCTAssertEqual(BrewStoreSection.backups.rawValue, "Backups")
        XCTAssertEqual(BrewStoreSection.settings.rawValue, "Settings")
    }

    @MainActor
    func testPackagePinningManagerOptimisticState() {
        let manager = BrewStorePackagePinningManager.shared
        let homebrewManager = HomebrewManager()

        // Test formula pinning
        let formula = BrewStorePackage(id: "ripgrep-test", name: "Ripgrep", description: "", homepage: "", version: "1.0", kind: .formula)
        manager.pin(packageID: formula.id, kind: .formula, manager: homebrewManager)
        XCTAssertTrue(manager.isPinned(packageID: "ripgrep-test"))

        manager.unpin(packageID: formula.id, kind: .formula, manager: homebrewManager)
        XCTAssertFalse(manager.isPinned(packageID: "ripgrep-test"))

        // Test cask pinning
        let cask = BrewStorePackage(id: "ghostty-test", name: "Ghostty", description: "", homepage: "", version: "1.0", kind: .cask)
        manager.pin(packageID: cask.id, kind: .cask, manager: homebrewManager)
        XCTAssertTrue(manager.isPinned(packageID: "ghostty-test"))

        manager.unpin(packageID: cask.id, kind: .cask, manager: homebrewManager)
        XCTAssertFalse(manager.isPinned(packageID: "ghostty-test"))
    }
}
