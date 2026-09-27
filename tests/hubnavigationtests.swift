@testable import BrewStore
import SwiftUI
import XCTest

final class HubNavigationTests: XCTestCase {
    func testHubDefinitionAndCompleteness() {
        let allHubs = BrewStoreHub.allCases
        XCTAssertEqual(allHubs.count, 5, "Expected exactly 5 hubs (Storefront, My Mac, Environment, Health & Maintenance, Settings)")

        for hub in allHubs {
            XCTAssertFalse(hub.id.isEmpty)
            XCTAssertFalse(hub.rawValue.isEmpty)
            XCTAssertFalse(hub.icon.isEmpty)
            XCTAssertEqual(hub.defaultSection.hub, hub, "Default section for hub \(hub.rawValue) must map back to the hub itself.")
        }
    }

    func testAllSectionsMapToCorrectHubs() {
        let sections = BrewStoreSection.allCases
        XCTAssertEqual(sections.count, 19)

        for section in sections {
            let hub = section.hub
            switch section {
            case .discover, .allPackages, .showdown, .allApps, .allFormulae, .stories, .toolkits, .categories:
                XCTAssertEqual(hub, .storefront, "\(section.rawValue) should belong to Storefront Hub")
            case .installed, .updates, .wishlist, .adoption, .topology:
                XCTAssertEqual(hub, .myMac, "\(section.rawValue) should belong to My Mac Hub")
            case .workspaces, .services, .taps, .creator:
                XCTAssertEqual(hub, .environment, "\(section.rawValue) should belong to Environment Hub")
            case .backups:
                XCTAssertEqual(hub, .health, "\(section.rawValue) should belong to Health Hub")
            case .settings:
                XCTAssertEqual(hub, .settings, "\(section.rawValue) should belong to Settings Hub")
            }
        }
    }

    func testMyMacSubModesRoundtrip() {
        let expectedSections: [(MyMacSubMode, BrewStoreSection)] = [
            (.installed, .installed),
            (.updates, .updates),
            (.wishlist, .wishlist),
            (.adoption, .adoption),
            (.topology, .topology)
        ]

        for (subMode, expectedSection) in expectedSections {
            XCTAssertEqual(subMode.section, expectedSection)
            XCTAssertEqual(MyMacSubMode(section: expectedSection), subMode)
            XCTAssertEqual(expectedSection.hub, .myMac)
        }

        // Other sections should return nil for MyMacSubMode
        XCTAssertNil(MyMacSubMode(section: .services))
        XCTAssertNil(MyMacSubMode(section: .discover))
        XCTAssertNil(MyMacSubMode(section: .backups))
    }

    func testEnvironmentSubModesRoundtrip() {
        let expectedSections: [(EnvironmentSubMode, BrewStoreSection)] = [
            (.services, .services),
            (.taps, .taps),
            (.creator, .creator)
        ]

        for (subMode, expectedSection) in expectedSections {
            XCTAssertEqual(subMode.section, expectedSection)
            XCTAssertEqual(EnvironmentSubMode(section: expectedSection), subMode)
            XCTAssertEqual(expectedSection.hub, .environment)
        }

        // Other sections should return nil for EnvironmentSubMode
        XCTAssertNil(EnvironmentSubMode(section: .installed))
        XCTAssertNil(EnvironmentSubMode(section: .discover))
    }

    func testHealthSubModesMapToHealthHub() {
        let modes = HealthSubMode.allCases
        XCTAssertEqual(modes.count, 3)

        for mode in modes {
            XCTAssertEqual(mode.section.hub, .health)
        }
    }

    func testConditionalStoryLookupReturnsNilForPackagesWithoutStory() {
        // Packages known NOT to have editorial stories in editorialstories.swift
        let nonStoryPackages = ["wget", "curl", "htop", "tree", "jq", "iterm2", "neofetch"]
        for pkgID in nonStoryPackages {
            XCTAssertNil(
                BrewStoreStory.story(containingPackageID: pkgID),
                "Package \(pkgID) should not have an editorial story."
            )
        }

        // Packages known TO have an editorial story in editorialstories.swift
        let storyPackages = ["ghostty", "raycast", "docker", "starship", "bat", "eza", "zoxide", "btop", "orbstack", "zed"]
        for pkgID in storyPackages {
            XCTAssertNotNil(
                BrewStoreStory.story(containingPackageID: pkgID),
                "Package \(pkgID) should have an editorial story."
            )
        }
    }

    func testURLSchemeHubRouting() {
        let routes: [(String, BrewStoreHub)] = [
            ("brewstore://services", .environment),
            ("brewstore://taps", .environment),
            ("brewstore://adopt", .myMac),
            ("brewstore://settings", .settings),
            ("brewstore://search", .storefront),
            ("brewstore://stacks", .storefront),
            ("brewstore://stories", .storefront)
        ]

        for (urlString, expectedHub) in routes {
            guard let url = URL(string: urlString),
                  let route = BrewStoreURLSchemeRouter.parse(url: url)
            else {
                XCTFail("Failed to parse URL: \(urlString)")
                continue
            }

            switch route {
            case .services:
                XCTAssertEqual(expectedHub, .environment)
            case .taps:
                XCTAssertEqual(expectedHub, .environment)
            case .adopt:
                XCTAssertEqual(expectedHub, .myMac)
            case .settings:
                XCTAssertEqual(expectedHub, .settings)
            case .search, .stacks, .stories, .open:
                XCTAssertEqual(expectedHub, .storefront)
            default:
                break
            }
        }
    }

    func testHubSubSectionsCompleteness() {
        for hub in BrewStoreHub.allCases {
            XCTAssertFalse(hub.subSections.isEmpty, "Every hub must have at least one sub-section")
            for subSection in hub.subSections {
                XCTAssertEqual(subSection.hub, hub, "Sub-section \(subSection.rawValue) must belong to hub \(hub.rawValue)")
            }
        }

        // Verify that every BrewStoreSection appears in exactly one hub's subSections
        let allSubSections = BrewStoreHub.allCases.flatMap(\.subSections)
        XCTAssertEqual(allSubSections.count, BrewStoreSection.allCases.count)
        XCTAssertEqual(Set(allSubSections), Set(BrewStoreSection.allCases))
    }

    @MainActor
    func testToolchainCompanionsModelRefreshAndItems() {
        let model = ToolchainCompanionsModel()
        model.refresh()

        // Must monitor 5 essential companions: speedtest-go, mas, trash, git, mole
        XCTAssertEqual(model.items.count, 5)
        let ids = Set(model.items.map(\.id))
        XCTAssertTrue(ids.contains("speedtest-go"))
        XCTAssertTrue(ids.contains("mas"))
        XCTAssertTrue(ids.contains("trash"))
        XCTAssertTrue(ids.contains("git"))
        XCTAssertTrue(ids.contains("mole"))

        for item in model.items {
            XCTAssertFalse(item.name.isEmpty)
            XCTAssertFalse(item.formulaName.isEmpty)
            XCTAssertFalse(item.category.isEmpty)
            XCTAssertFalse(item.icon.isEmpty)
            XCTAssertFalse(item.description.isEmpty)
            XCTAssertFalse(item.detailStatus.isEmpty)
        }

        // Git should be detected on macOS
        if let gitItem = model.items.first(where: { $0.id == "git" }) {
            XCTAssertTrue(gitItem.isInstalled)
            XCTAssertFalse(gitItem.canInstall)
        }
    }
}
