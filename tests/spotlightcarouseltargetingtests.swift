@testable import BrewStore
import XCTest

@MainActor
final class SpotlightCarouselTargetingTests: XCTestCase {
    func testAutoAdvanceAllowedWhenIdleAndUnpaused() {
        let coordinator = SpotlightCarouselCoordinator(idleThresholdSeconds: 10.0)
        XCTAssertFalse(coordinator.picks.isEmpty)
        coordinator.currentIndex = 0

        // Initially not enough time has passed
        XCTAssertFalse(coordinator.canAutoAdvance(now: Date()))

        // Simulate 15 seconds of idle time
        let future = Date().addingTimeInterval(15.0)
        XCTAssertTrue(coordinator.canAutoAdvance(now: future))

        // Advancing moves to the next pick
        let advanced = coordinator.advanceIfAllowed(now: future)
        XCTAssertTrue(advanced)
        XCTAssertEqual(coordinator.currentIndex, 1)
    }

    func testAutoAdvanceBlockedWhileInteractingWithHeroAction() {
        let coordinator = SpotlightCarouselCoordinator(idleThresholdSeconds: 10.0)
        coordinator.currentIndex = 0
        let future = Date().addingTimeInterval(15.0)

        // Mark hero action interaction active
        coordinator.setInteractingWithHeroAction(true)
        XCTAssertTrue(coordinator.isInteractingWithHeroAction)

        // Even with enough elapsed time, auto-advance must be paused/blocked
        XCTAssertFalse(coordinator.canAutoAdvance(now: future))
        let advanced = coordinator.advanceIfAllowed(now: future)
        XCTAssertFalse(advanced)
        XCTAssertEqual(coordinator.currentIndex, 0)

        // When interaction ends, lastUserActivityTime is refreshed
        coordinator.setInteractingWithHeroAction(false)
        XCTAssertFalse(coordinator.isInteractingWithHeroAction)
        // Immediately after ending interaction, elapsed time is 0, so still blocked
        XCTAssertFalse(coordinator.canAutoAdvance(now: Date()))
    }

    func testAutoAdvanceBlockedWhileHovering() {
        let coordinator = SpotlightCarouselCoordinator(idleThresholdSeconds: 10.0)
        let future = Date().addingTimeInterval(15.0)

        coordinator.setHovering(true)
        XCTAssertTrue(coordinator.isHovering)
        XCTAssertFalse(coordinator.canAutoAdvance(now: future))
        XCTAssertFalse(coordinator.advanceIfAllowed(now: future))

        coordinator.setHovering(false)
        XCTAssertFalse(coordinator.isHovering)
        XCTAssertTrue(coordinator.canAutoAdvance(now: future))
    }

    func testAutoAdvanceBlockedWhenPausedOrReduceMotion() {
        let coordinator = SpotlightCarouselCoordinator(idleThresholdSeconds: 10.0)
        let future = Date().addingTimeInterval(15.0)

        coordinator.isPaused = true
        XCTAssertFalse(coordinator.canAutoAdvance(now: future))

        coordinator.isPaused = false
        XCTAssertTrue(coordinator.canAutoAdvance(now: future, reduceMotion: false))
        XCTAssertFalse(coordinator.canAutoAdvance(now: future, reduceMotion: true))
    }

    func testAutoAdvanceBlockedWhileWishlistFeedbackIsActive() {
        let coordinator = SpotlightCarouselCoordinator(idleThresholdSeconds: 10.0)
        let future = Date().addingTimeInterval(15.0)

        coordinator.activeFeedback = SpotlightHeroFeedback(
            packageID: "neovim",
            packageName: "Neovim",
            isWishlisted: true,
            message: "Added Neovim to Wishlist"
        )

        XCTAssertFalse(coordinator.canAutoAdvance(now: future))
        XCTAssertFalse(coordinator.advanceIfAllowed(now: future))

        coordinator.clearFeedback(for: "neovim")
        XCTAssertNil(coordinator.activeFeedback)
        XCTAssertTrue(coordinator.canAutoAdvance(now: future))
    }

    func testWishlistFeedbackIsStrictlyBoundToSelectedPackageID() {
        let coordinator = SpotlightCarouselCoordinator()
        guard let firstPick = coordinator.picks.first else {
            XCTFail("Editorial picks must not be empty")
            return
        }

        let wishlistManager = BrewStoreWishlistManager.shared
        let originalWishlistState = wishlistManager.isWishlisted(id: firstPick.id)

        // Toggle wishlist for first pick
        coordinator.toggleWishlist(for: firstPick, wishlistManager: wishlistManager)

        // Feedback must match first pick's ID
        XCTAssertNotNil(coordinator.activeFeedback)
        XCTAssertEqual(coordinator.activeFeedback?.packageID, firstPick.id)
        XCTAssertEqual(coordinator.feedback(for: firstPick.id)?.packageID, firstPick.id)

        // Feedback must NOT be exposed for a different package ID
        XCTAssertNil(coordinator.feedback(for: "unrelated-package-id"))

        // Auto-advance is blocked while interacting
        XCTAssertTrue(coordinator.isInteractingWithHeroAction)

        // Clean up state
        if wishlistManager.isWishlisted(id: firstPick.id) != originalWishlistState {
            wishlistManager.toggleWishlist(id: firstPick.id)
        }
        coordinator.clearFeedback()
        coordinator.setInteractingWithHeroAction(false)
    }

    func testClearingFeedbackForDifferentPackageDoesNotAffectActive() {
        let coordinator = SpotlightCarouselCoordinator()
        coordinator.activeFeedback = SpotlightHeroFeedback(
            packageID: "tableplus",
            packageName: "TablePlus",
            isWishlisted: true,
            message: "Added TablePlus to Wishlist"
        )

        // Clearing a different ID does not clear active feedback
        coordinator.clearFeedback(for: "neovim")
        XCTAssertNotNil(coordinator.activeFeedback)
        XCTAssertEqual(coordinator.activeFeedback?.packageID, "tableplus")

        // Clearing matching ID clears it
        coordinator.clearFeedback(for: "tableplus")
        XCTAssertNil(coordinator.activeFeedback)
    }

    func testWishlistToggleRejectsStalePickWithoutMutation() {
        let coordinator = SpotlightCarouselCoordinator()
        guard coordinator.picks.count >= 2 else {
            XCTFail("Need at least 2 picks to test carousel positioning independence")
            return
        }

        let pick0 = coordinator.picks[0]
        let pick1 = coordinator.picks[1]
        let wishlist = BrewStoreWishlistManager.shared

        let pick0Initial = wishlist.isWishlisted(id: pick0.id)
        let pick1Initial = wishlist.isWishlisted(id: pick1.id)

        // Current index is on pick 1, but the captured action still points at pick 0.
        coordinator.currentIndex = 1
        coordinator.toggleWishlist(for: pick0, wishlistManager: wishlist)

        // A stale action must be ignored rather than changing the wrong package.
        XCTAssertEqual(wishlist.isWishlisted(id: pick0.id), pick0Initial)
        XCTAssertEqual(wishlist.isWishlisted(id: pick1.id), pick1Initial)
        XCTAssertNil(coordinator.activeFeedback)

        // The visible pick remains actionable and can be restored.
        coordinator.toggleWishlist(for: pick1, wishlistManager: wishlist)
        XCTAssertNotEqual(wishlist.isWishlisted(id: pick1.id), pick1Initial)
        XCTAssertEqual(coordinator.activeFeedback?.packageID, pick1.id)
        coordinator.toggleWishlist(for: pick1, wishlistManager: wishlist)
        XCTAssertEqual(wishlist.isWishlisted(id: pick1.id), pick1Initial)
        coordinator.clearFeedback()
        coordinator.setInteractingWithHeroAction(false)
    }
}
