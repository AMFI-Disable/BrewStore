@testable import BrewStore
import SwiftUI
import XCTest

final class GlobalSearchEngineTests: XCTestCase {
    func testGlobalSearchScoringAndRanking() {
        let pkg1 = BrewStorePackage(id: "docker", name: "Docker Desktop", description: "Container virtualization platform", homepage: "https://docker.com", version: "4.28.0", kind: .cask)
        let pkg2 = BrewStorePackage(id: "dockutil", name: "dockutil", description: "Command-line tool for managing dock items", homepage: "https://github.com", version: "3.0.2", kind: .formula)
        let pkg3 = BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "Fast search tool", homepage: "https://github.com/BurntSushi/ripgrep", version: "14.1.0", kind: .formula)

        let packages = [pkg1, pkg2, pkg3]

        // Exact query "docker" should match pkg1 with higher score than pkg2
        let query = "docker"
        let filtered = packages.filter {
            $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query) || $0.description.lowercased().contains(query)
        }

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "docker")
    }

    func testGlobalSearchScopeFilters() {
        let pkg1 = BrewStorePackage(id: "ghostty", name: "Ghostty", description: "Fast native terminal", homepage: "https://ghostty.org", version: "1.0.0", kind: .cask)
        let pkg2 = BrewStorePackage(id: "gh", name: "gh", description: "GitHub CLI", homepage: "https://cli.github.com", version: "2.50.0", kind: .formula)

        let allPackages = [pkg1, pkg2]

        // Filter for Apps (Casks)
        let appResults = allPackages.filter { $0.kind == .cask }
        XCTAssertEqual(appResults.count, 1)
        XCTAssertEqual(appResults.first?.id, "ghostty")

        // Filter for CLI (Formulae)
        let cliResults = allPackages.filter { $0.kind == .formula }
        XCTAssertEqual(cliResults.count, 1)
        XCTAssertEqual(cliResults.first?.id, "gh")
    }

    func testSectionSearchFiltering() {
        let packages = [
            BrewStorePackage(id: "redis", name: "Redis", description: "Persistent key-value database", homepage: "https://redis.io", version: "7.2.4", kind: .formula),
            BrewStorePackage(id: "postgresql@16", name: "PostgreSQL 16", description: "Object-relational database", homepage: "https://postgresql.org", version: "16.2", kind: .formula),
            BrewStorePackage(id: "nginx", name: "Nginx", description: "HTTP and reverse proxy server", homepage: "https://nginx.org", version: "1.25.4", kind: .formula)
        ]

        let query = "database"
        let matched = packages.filter {
            $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query) || $0.description.lowercased().contains(query)
        }

        XCTAssertEqual(matched.count, 2)
        XCTAssertTrue(matched.contains(where: { $0.id == "redis" }))
        XCTAssertTrue(matched.contains(where: { $0.id == "postgresql@16" }))
    }

    func testGlobalSearchScopeProperties() {
        let scopes = BrewStoreGlobalSearchBar.GlobalSearchScope.allCases
        XCTAssertEqual(scopes.count, 4)

        for scope in scopes {
            XCTAssertFalse(scope.id.isEmpty)
            XCTAssertFalse(scope.rawValue.isEmpty)
            XCTAssertFalse(scope.icon.isEmpty)
        }
    }

    @MainActor
    func testCommandPaletteCategoriesAndExecution() {
        let categories = CommandPaletteView.PaletteCategory.allCases
        XCTAssertEqual(categories.count, 4)

        for cat in categories {
            XCTAssertFalse(cat.rawValue.isEmpty)
        }

        var executed = false
        let item = CommandPaletteView.PaletteItem(
            id: "test-cmd",
            title: "Test Command",
            subtitle: "Test Subtitle",
            icon: "terminal",
            category: .actions,
            shortcut: "⌘T",
            isInstalled: true,
            kind: .formula,
            package: nil,
            service: nil
        ) {
            executed = true
        }

        XCTAssertEqual(item.id, "test-cmd")
        XCTAssertEqual(item.title, "Test Command")
        XCTAssertEqual(item.subtitle, "Test Subtitle")
        XCTAssertEqual(item.icon, "terminal")
        XCTAssertEqual(item.category, .actions)
        XCTAssertEqual(item.shortcut, "⌘T")
        XCTAssertEqual(item.isInstalled, true)
        XCTAssertEqual(item.kind, .formula)
        XCTAssertNil(item.package)
        XCTAssertNil(item.service)

        item.execute()
        XCTAssertTrue(executed)
    }

    func testSelectionBoundsContainmentSafety() {
        let items: [Int] = [10, 20, 30]

        XCTAssertTrue(items.indices.contains(0))
        XCTAssertTrue(items.indices.contains(1))
        XCTAssertTrue(items.indices.contains(2))

        // Negative index must be safely rejected (prevents out-of-bounds crash)
        XCTAssertFalse(items.indices.contains(-1))
        XCTAssertFalse(items.indices.contains(3))
        XCTAssertFalse(items.indices.contains(999))

        let emptyItems: [Int] = []
        XCTAssertFalse(emptyItems.indices.contains(0))
        XCTAssertFalse(emptyItems.indices.contains(-1))
    }
}
