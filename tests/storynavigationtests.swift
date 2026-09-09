@testable import BrewStore
import XCTest

final class StoryNavigationTests: XCTestCase {
    func testEveryEditorialPickCanOpenAnEditorialStory() {
        for pick in BrewStoreEditorialPick.allPicks {
            XCTAssertNotNil(
                BrewStoreStory.story(containingPackageID: pick.id),
                "No story is associated with editorial pick \(pick.id)."
            )
        }
    }

    func testStoryLookupIsCaseInsensitiveAndRejectsUnknownPackages() {
        XCTAssertEqual(
            BrewStoreStory.story(containingPackageID: "GHOSTTY")?.id,
            "terminal-mastery"
        )
        XCTAssertNil(BrewStoreStory.story(containingPackageID: "not-a-story-package"))
    }
}
