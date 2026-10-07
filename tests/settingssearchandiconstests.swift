@testable import BrewStore
import XCTest

final class SettingsSearchAndIconsTests: XCTestCase {
    // MARK: - Icon URL Tests

    func testPackageIconURLResolutionForCask() {
        let pkg = BrewStorePackage(
            id: "visual-studio-code",
            name: "Visual Studio Code",
            description: "Code editor",
            homepage: "https://code.visualstudio.com",
            version: "1.93.0",
            kind: .cask
        )

        let iconURL = pkg.iconURL
        XCTAssertNotNil(iconURL)
        XCTAssertEqual(iconURL?.host, "www.google.com")
        XCTAssertTrue(iconURL?.absoluteString.contains("code.visualstudio.com") ?? false)
    }

    func testPackageIconURLResolutionForFormula() {
        let pkg = BrewStorePackage(
            id: "git",
            name: "Git",
            description: "Fast version control",
            homepage: "https://git-scm.com",
            version: "2.46.0",
            kind: .formula
        )

        let iconURL = pkg.iconURL
        XCTAssertNotNil(iconURL)
        XCTAssertEqual(iconURL?.host, "www.google.com")
        XCTAssertTrue(iconURL?.absoluteString.contains("git-scm.com") ?? false)
    }

    func testPackageIconURLResolutionWithoutScheme() {
        let pkg = BrewStorePackage(
            id: "iterm2",
            name: "iTerm2",
            description: "Terminal emulator",
            homepage: "iterm2.com",
            version: "3.5.0",
            kind: .cask
        )

        let iconURL = pkg.iconURL
        XCTAssertNotNil(iconURL)
        XCTAssertTrue(iconURL?.absoluteString.contains("iterm2.com") ?? false)
    }

    func testPackageIconURLResolutionWithEmptyOrWhitespace() {
        let emptyPkg = BrewStorePackage(
            id: "unknown",
            name: "Unknown",
            description: "",
            homepage: "   ",
            version: "1.0",
            kind: .cask
        )
        XCTAssertNil(emptyPkg.iconURL)
    }

    func testDiscoveryItemIconURLResolution() {
        let caskItem = BrewStoreDiscoveryItem(
            id: "firefox",
            name: "Firefox",
            description: "Web browser",
            homepage: "https://www.mozilla.org/firefox/",
            version: "130.0",
            kind: .cask,
            installCount30Days: 1000,
            tap: nil,
            license: nil,
            aliases: [],
            dependencies: [],
            artifacts: []
        )
        XCTAssertNotNil(caskItem.iconURL)
        XCTAssertTrue(caskItem.iconURL?.absoluteString.contains("www.mozilla.org") ?? false)

        let formulaItem = BrewStoreDiscoveryItem(
            id: "wget",
            name: "Wget",
            description: "Internet file retriever",
            homepage: "https://www.gnu.org/software/wget/",
            version: "1.24.5",
            kind: .formula,
            installCount30Days: 800,
            tap: nil,
            license: nil,
            aliases: [],
            dependencies: [],
            artifacts: []
        )
        XCTAssertNotNil(formulaItem.iconURL)
        XCTAssertTrue(formulaItem.iconURL?.absoluteString.contains("www.gnu.org") ?? false)
    }

    // MARK: - Settings Search Tests

    func testSettingsSearchEngineAllItemsCountAndIntegrity() {
        XCTAssertFalse(SettingsSearchEngine.allItems.isEmpty)
        XCTAssertGreaterThanOrEqual(SettingsSearchEngine.allItems.count, 35)

        for item in SettingsSearchEngine.allItems {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.summary.isEmpty)
            XCTAssertFalse(item.icon.isEmpty)
            XCTAssertFalse(item.breadcrumb.isEmpty)
        }
    }

    func testSettingsSearchEngineQueryMatching() {
        let themeResults = SettingsSearchEngine.search(query: "theme")
        XCTAssertFalse(themeResults.isEmpty)
        XCTAssertTrue(themeResults.contains { $0.tab == .appearance })

        let mirrorResults = SettingsSearchEngine.search(query: "mirror")
        XCTAssertFalse(mirrorResults.isEmpty)
        XCTAssertTrue(mirrorResults.contains { $0.tab == .network })

        let doctorResults = SettingsSearchEngine.search(query: "diagnostics")
        XCTAssertFalse(doctorResults.isEmpty)
        XCTAssertTrue(doctorResults.contains { $0.tab == .doctor })

        let refreshResults = SettingsSearchEngine.search(query: "refresh")
        XCTAssertFalse(refreshResults.isEmpty)
        XCTAssertTrue(refreshResults.contains { $0.tab == .general })
    }

    func testSettingsSearchEngineCaseInsensitivityAndKeywords() {
        let upperResults = SettingsSearchEngine.search(query: "GIST")
        let lowerResults = SettingsSearchEngine.search(query: "gist")
        XCTAssertEqual(upperResults.count, lowerResults.count)
        XCTAssertFalse(upperResults.isEmpty)
        XCTAssertTrue(upperResults.contains { $0.tab == .snapshots })

        let keywordResults = SettingsSearchEngine.search(query: "tuna")
        XCTAssertFalse(keywordResults.isEmpty)
        XCTAssertTrue(keywordResults.contains { $0.id == "network_mirrors" })
    }

    func testSettingsSearchEngineEmptyAndWhitespaceQueries() {
        XCTAssertTrue(SettingsSearchEngine.search(query: "").isEmpty)
        XCTAssertTrue(SettingsSearchEngine.search(query: "    ").isEmpty)
        XCTAssertTrue(SettingsSearchEngine.search(query: "nonexistentgibberishstringxyz").isEmpty)
    }

    func testSettingsTabProperties() {
        let allTabs = SettingsTab.allCases
        XCTAssertEqual(allTabs.count, 7)
        for tab in allTabs {
            XCTAssertFalse(tab.id.isEmpty)
            XCTAssertFalse(tab.icon.isEmpty)
        }
    }
}
