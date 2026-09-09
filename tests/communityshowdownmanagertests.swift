@testable import BrewStore
import XCTest

@MainActor
final class CommunityShowdownManagerTests: XCTestCase {
    private func makePackage(
        id: String,
        name: String? = nil,
        kind: BrewPackageKind = .formula,
        tap: String? = nil,
        installed: Bool = false
    ) -> BrewStorePackage {
        BrewStorePackage(
            id: id,
            name: name ?? id.capitalized,
            description: "Test package for showdown",
            homepage: "https://example.com",
            version: "1.0.0",
            kind: kind,
            isInstalled: installed,
            tap: tap
        )
    }

    override func setUp() {
        super.setUp()
        CommunityShowdownManager().resetForTesting()
    }

    func testInitialHallOfFameContainsGiants() {
        let manager = CommunityShowdownManager()
        let ids = Set(manager.hallOfFame.map { $0.packageID.lowercased() })

        XCTAssertTrue(ids.contains("git"))
        XCTAssertTrue(ids.contains("docker"))
        XCTAssertTrue(ids.contains("visual-studio-code"))
    }

    func testEligibilityFiltersOutHallOfFamePackages() {
        let manager = CommunityShowdownManager()
        let gitPkg = makePackage(id: "git", name: "Git", kind: .formula)

        let result = manager.isEligibleForNomination(gitPkg)
        XCTAssertFalse(result.eligible)
        XCTAssertTrue(result.reason?.contains("Hall of Fame") ?? false)
    }

    func testEligibilityFiltersOutCustomThirdPartyTaps() {
        let manager = CommunityShowdownManager()
        let customTapPkg = makePackage(id: "custom-tool", tap: "somebody/custom-tap")

        let result = manager.isEligibleForNomination(customTapPkg)
        XCTAssertFalse(result.eligible)
        XCTAssertTrue(result.reason?.contains("Only official formulas") ?? false)
    }

    func testEligibilityAllowsOfficialAndNewPackages() {
        let manager = CommunityShowdownManager()
        let officialFormula = makePackage(id: "fresh-tool", tap: "homebrew/core")
        let officialCask = makePackage(id: "fresh-app", kind: .cask, tap: "homebrew/cask")
        let defaultFormula = makePackage(id: "untapped-tool", tap: nil)

        XCTAssertTrue(manager.isEligibleForNomination(officialFormula).eligible)
        XCTAssertTrue(manager.isEligibleForNomination(officialCask).eligible)
        XCTAssertTrue(manager.isEligibleForNomination(defaultFormula).eligible)
    }

    func testEligibilityRejectsAlreadyNominatedPackages() {
        let manager = CommunityShowdownManager()
        // 'ripgrep' is already in default season nominees
        let ripgrepPkg = makePackage(id: "ripgrep", name: "ripgrep")

        let result = manager.isEligibleForNomination(ripgrepPkg)
        XCTAssertFalse(result.eligible)
        XCTAssertTrue(result.reason?.contains("already been nominated") ?? false)
    }

    func testNominatePackageAddsToSeason() async {
        let manager = CommunityShowdownManager()
        let newPkg = makePackage(id: "zoxide", name: "Zoxide")

        let brewManager = HomebrewManager()
        let success = await manager.nominatePackage(newPkg, manager: brewManager, token: nil)

        XCTAssertTrue(success)
        XCTAssertEqual(manager.currentSeason?.nominees.first?.packageID, "zoxide")
        XCTAssertEqual(manager.currentSeason?.nominees.first?.voteCount, 1)
        XCTAssertEqual(manager.currentSeason?.nominees.first?.hasVoted, true)
    }

    func testToggleVoteIncrementsAndDecrements() async {
        let manager = CommunityShowdownManager()
        guard let firstNominee = manager.currentSeason?.nominees.first else {
            XCTFail("Missing nominees in default season")
            return
        }

        let initialVotes = firstNominee.voteCount

        // 1. Upvote
        let successVote = await manager.toggleVote(nominee: firstNominee, token: nil)
        XCTAssertTrue(successVote)

        let votedNominee = manager.currentSeason?.nominees.first(where: { $0.id == firstNominee.id })
        XCTAssertEqual(votedNominee?.voteCount, initialVotes + 1)
        XCTAssertEqual(votedNominee?.hasVoted, true)

        // 2. Remove vote
        if let current = votedNominee {
            let successUnvote = await manager.toggleVote(nominee: current, token: nil)
            XCTAssertTrue(successUnvote)

            let unvotedNominee = manager.currentSeason?.nominees.first(where: { $0.id == firstNominee.id })
            XCTAssertEqual(unvotedNominee?.voteCount, initialVotes)
            XCTAssertEqual(unvotedNominee?.hasVoted, false)
        }
    }

    func testVoteMatchupUpdatesTallyAndPercentage() async {
        let manager = CommunityShowdownManager()
        guard let matchup = manager.currentSeason?.matchups.first else {
            XCTFail("Missing matchups in default season")
            return
        }

        let candidateAID = matchup.candidateA.id
        let initialVotesA = matchup.votesA

        let success = await manager.voteMatchup(
            matchupID: matchup.id,
            candidateChoice: candidateAID,
            token: nil
        )

        XCTAssertTrue(success)
        let updated = manager.currentSeason?.matchups.first(where: { $0.id == matchup.id })
        XCTAssertEqual(updated?.votesA, initialVotesA + 1)
        XCTAssertEqual(updated?.userChoice, candidateAID)
    }

    func testSingleVotePolicySwitchesVoteBetweenNominees() async {
        let manager = CommunityShowdownManager()
        guard let nominees = manager.currentSeason?.nominees, nominees.count >= 2 else {
            XCTFail("Requires at least 2 nominees")
            return
        }

        let first = nominees[0]
        let second = nominees[1]
        let initialVotesFirst = first.voteCount
        let initialVotesSecond = second.voteCount

        // 1. Vote for first nominee
        _ = await manager.toggleVote(nominee: first, token: nil)
        let afterFirstVote = manager.currentSeason?.nominees
        XCTAssertEqual(afterFirstVote?.first(where: { $0.id == first.id })?.voteCount, initialVotesFirst + 1)
        XCTAssertEqual(afterFirstVote?.first(where: { $0.id == first.id })?.hasVoted, true)
        XCTAssertEqual(afterFirstVote?.first(where: { $0.id == second.id })?.voteCount, initialVotesSecond)
        XCTAssertEqual(afterFirstVote?.first(where: { $0.id == second.id })?.hasVoted, false)

        // 2. Vote for second nominee -> should automatically move single vote
        _ = await manager.toggleVote(nominee: second, token: nil)
        let afterSecondVote = manager.currentSeason?.nominees
        XCTAssertEqual(afterSecondVote?.first(where: { $0.id == first.id })?.voteCount, initialVotesFirst)
        XCTAssertEqual(afterSecondVote?.first(where: { $0.id == first.id })?.hasVoted, false)
        XCTAssertEqual(afterSecondVote?.first(where: { $0.id == second.id })?.voteCount, initialVotesSecond + 1)
        XCTAssertEqual(afterSecondVote?.first(where: { $0.id == second.id })?.hasVoted, true)

        // Verify total voted count across entire season is exactly 1
        let totalVoted = afterSecondVote?.filter(\.hasVoted).count ?? 0
        XCTAssertEqual(totalVoted, 1)
    }

    func testNominationTransfersExistingVote() async {
        let manager = CommunityShowdownManager()
        guard let first = manager.currentSeason?.nominees.first else {
            XCTFail("Requires nominee")
            return
        }

        // Vote for first
        _ = await manager.toggleVote(nominee: first, token: nil)
        XCTAssertEqual(manager.currentSeason?.nominees.filter(\.hasVoted).count, 1)

        // Now nominate a new package
        let newPkg = makePackage(id: "starship", name: "Starship")
        let success = await manager.nominatePackage(newPkg, manager: HomebrewManager(), token: nil)
        XCTAssertTrue(success)

        // Assert new package has the vote, and first nominee lost the vote
        let nominees = manager.currentSeason?.nominees ?? []
        XCTAssertEqual(nominees.filter(\.hasVoted).count, 1)
        XCTAssertEqual(nominees.first(where: { $0.packageID == "starship" })?.hasVoted, true)
        XCTAssertEqual(nominees.first(where: { $0.id == first.id })?.hasVoted, false)
    }
}
