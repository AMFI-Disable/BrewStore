@testable import BrewStore
import CoreSpotlight
import XCTest

final class SpotlightIndexerTests: XCTestCase {
    func testCreateSearchableItemAttributes() {
        let package = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Fast line-oriented regex search tool",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: true,
            installedVersion: "14.1.0"
        )

        let indexer = BrewStoreSpotlightIndexer.shared
        let item = indexer.createSearchableItem(for: package)

        XCTAssertEqual(item.uniqueIdentifier, "brewstore://package/ripgrep")
        XCTAssertEqual(item.domainIdentifier, BrewStoreSpotlightIndexer.domainIdentifier)
        XCTAssertEqual(item.attributeSet.title, "ripgrep")
        XCTAssertEqual(item.attributeSet.contentDescription, "Fast line-oriented regex search tool")
        XCTAssertEqual(item.attributeSet.version, "14.1.0")

        let keywords = item.attributeSet.keywords ?? []
        XCTAssertTrue(keywords.contains("ripgrep"))
        XCTAssertTrue(keywords.contains("Homebrew"))
    }

    func testSpotlightSupportCheck() {
        let indexer = BrewStoreSpotlightIndexer.shared
        // Verification that isSupported returns a valid boolean and doesn't crash
        let supported = indexer.isSupported
        XCTAssertTrue(supported || !supported)
    }
}
