@testable import BrewStore
import SwiftUI
import XCTest

@MainActor
final class DetailModalOverlayTests: XCTestCase {
    func testOverlayItemBindingDismissal() {
        var testItem: BrewStorePackage? = BrewStorePackage(
            id: "wget",
            name: "wget",
            description: "Internet file retriever",
            homepage: "https://www.gnu.org/software/wget/",
            version: "1.24.5",
            kind: .formula
        )

        let binding = Binding<BrewStorePackage?>(
            get: { testItem },
            set: { testItem = $0 }
        )

        XCTAssertNotNil(binding.wrappedValue)

        // Simulating backdrop tap setting item to nil
        binding.wrappedValue = nil
        XCTAssertNil(testItem)
    }

    func testPackageDetailViewDismissCallback() {
        let manager = HomebrewManager()
        let package = BrewStorePackage(
            id: "git",
            name: "git",
            description: "Fast, scalable, distributed revision control system",
            homepage: "https://git-scm.com",
            version: "2.44.0",
            kind: .formula
        )

        var dismissed = false
        let detailView = PackageDetailView(manager: manager, package: package, onDismiss: {
            dismissed = true
        })

        XCTAssertFalse(dismissed)
        detailView.onDismiss?()
        XCTAssertTrue(dismissed)
    }

    func testStoryDetailViewDismissCallback() {
        let manager = HomebrewManager()
        let story = BrewStoreStory(
            id: "test-story",
            eyebrow: "Spotlight",
            title: "Top 5 CLI Utilities",
            subtitle: "Boost your productivity",
            gradientColors: ["#ff0000", "#0000ff"],
            readTimeMinutes: 3,
            bodyMarkdown: "Great tools.",
            featuredPackageIDs: ["wget", "git"]
        )

        var dismissed = false
        let storyView = StoryDetailView(
            manager: manager,
            story: story,
            onDismiss: {
                dismissed = true
            }
        )

        XCTAssertFalse(dismissed)
        storyView.onDismiss?()
        XCTAssertTrue(dismissed)
    }
}
