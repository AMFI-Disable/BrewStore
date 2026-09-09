import Foundation
import SwiftUI

struct SpotlightHeroFeedback: Equatable {
    let packageID: String
    let packageName: String
    let isWishlisted: Bool
    let message: String
}

@MainActor
final class SpotlightCarouselCoordinator: ObservableObject {
    @Published var currentIndex: Int = 0
    @Published var isHovering: Bool = false
    @Published var isPaused: Bool = false
    @Published var isInteractingWithHeroAction: Bool = false
    @Published var activeFeedback: SpotlightHeroFeedback?
    @Published var lastUserActivityTime: Date = Date()

    let picks: [BrewStoreEditorialPick]
    let idleThresholdSeconds: TimeInterval
    private var feedbackDismissTask: Task<Void, Never>?

    init(
        picks: [BrewStoreEditorialPick] = BrewStoreEditorialPick.allPicks,
        idleThresholdSeconds: TimeInterval = 120.0
    ) {
        self.picks = picks
        self.idleThresholdSeconds = idleThresholdSeconds
    }

    var currentPick: BrewStoreEditorialPick? {
        guard picks.indices.contains(currentIndex) else { return nil }
        return picks[currentIndex]
    }

    func feedback(for packageID: String) -> SpotlightHeroFeedback? {
        guard let feedback = activeFeedback, feedback.packageID == packageID else {
            return nil
        }
        return feedback
    }

    func recordUserActivity() {
        lastUserActivityTime = Date()
    }

    func setInteractingWithHeroAction(_ interacting: Bool) {
        isInteractingWithHeroAction = interacting
        recordUserActivity()
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            recordUserActivity()
        }
    }

    func canAutoAdvance(now: Date = Date(), reduceMotion: Bool = false) -> Bool {
        guard !picks.isEmpty else { return false }
        guard !isPaused else { return false }
        guard !reduceMotion else { return false }
        guard !isHovering else { return false }
        guard !isInteractingWithHeroAction else { return false }
        guard activeFeedback == nil else { return false }
        let elapsed = now.timeIntervalSince(lastUserActivityTime)
        return elapsed >= idleThresholdSeconds
    }

    @discardableResult
    func advanceIfAllowed(now: Date = Date(), reduceMotion: Bool = false) -> Bool {
        guard canAutoAdvance(now: now, reduceMotion: reduceMotion) else {
            return false
        }
        guard !picks.isEmpty else { return false }
        currentIndex = (currentIndex + 1) % picks.count
        return true
    }

    func previousPick() {
        guard !picks.isEmpty else { return }
        recordUserActivity()
        currentIndex = (currentIndex - 1 + picks.count) % picks.count
    }

    func nextPick() {
        guard !picks.isEmpty else { return }
        recordUserActivity()
        currentIndex = (currentIndex + 1) % picks.count
    }

    func selectPick(id: String) {
        guard let index = picks.firstIndex(where: { $0.id == id }) else { return }
        recordUserActivity()
        currentIndex = index
    }

    func toggleWishlist(for pick: BrewStoreEditorialPick, wishlistManager: BrewStoreWishlistManager? = nil) {
        // Accessibility actions can arrive after the carousel has advanced. Never
        // apply a captured action to a different visible pick.
        guard let currentPick, currentPick.id == pick.id, currentPick.kind == pick.kind else {
            activeFeedback = nil
            return
        }

        // Keep the confirmation message attached to the pick the user acted on.
        // Pausing also prevents the hero from changing while that feedback is read.
        isPaused = true
        setInteractingWithHeroAction(true)
        let manager = wishlistManager ?? BrewStoreWishlistManager.shared
        let isCurrentlyWishlisted = manager.isWishlisted(id: pick.id)
        let willBeWishlisted = !isCurrentlyWishlisted

        manager.toggleWishlist(id: pick.id)

        let message = willBeWishlisted ? "Added \(pick.name) to Wishlist" : "Removed \(pick.name) from Wishlist"
        activeFeedback = SpotlightHeroFeedback(
            packageID: pick.id,
            packageName: pick.name,
            isWishlisted: willBeWishlisted,
            message: message
        )

        feedbackDismissTask?.cancel()
        feedbackDismissTask = Task { [weak self, targetID = pick.id] in
            try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.activeFeedback?.packageID == targetID {
                    self?.activeFeedback = nil
                }
                self?.setInteractingWithHeroAction(false)
            }
        }
    }

    func clearFeedback(for packageID: String? = nil) {
        if let packageID {
            if activeFeedback?.packageID == packageID {
                activeFeedback = nil
            }
        } else {
            activeFeedback = nil
        }
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil
    }

    deinit {
        feedbackDismissTask?.cancel()
    }
}
