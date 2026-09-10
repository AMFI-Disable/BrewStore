@testable import BrewStore
import XCTest

final class FuzzySearchEngineTests: XCTestCase {
    func testExactMatchHasHighestScore() {
        let exact = BrewStoreFuzzySearchEngine.score(query: "node", target: "node")
        let prefix = BrewStoreFuzzySearchEngine.score(query: "node", target: "nodejs")
        let partial = BrewStoreFuzzySearchEngine.score(query: "node", target: "libnode-extra")

        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, partial)
    }

    func testPrefixMatchScoring() {
        let score = BrewStoreFuzzySearchEngine.score(query: "rip", target: "ripgrep")
        XCTAssertGreaterThanOrEqual(score, 800)
    }

    func testAcronymAndBoundaryMatching() {
        let vscScore = BrewStoreFuzzySearchEngine.score(query: "vsc", target: "visual-studio-code")
        let rgScore = BrewStoreFuzzySearchEngine.score(query: "rg", target: "ripgrep")

        XCTAssertGreaterThan(vscScore, 0)
        XCTAssertGreaterThan(rgScore, 0)
    }

    func testSubsequenceFuzzyMatch() {
        let matchScore = BrewStoreFuzzySearchEngine.score(query: "pql", target: "postgresql")
        let noMatchScore = BrewStoreFuzzySearchEngine.score(query: "xyz", target: "postgresql")

        XCTAssertGreaterThan(matchScore, 0)
        XCTAssertEqual(noMatchScore, 0)
    }

    func testEmptyInputsReturnZero() {
        XCTAssertEqual(BrewStoreFuzzySearchEngine.score(query: "", target: "git"), 0)
        XCTAssertEqual(BrewStoreFuzzySearchEngine.score(query: "git", target: ""), 0)
        XCTAssertEqual(BrewStoreFuzzySearchEngine.score(query: "   ", target: "git"), 0)
    }

    func testBestScoreAcrossMultipleFields() {
        let targets = ["ripgrep", "rg", "Fast line-oriented regex search tool"]
        let score = BrewStoreFuzzySearchEngine.bestScore(query: "regex", targets: targets)
        XCTAssertGreaterThan(score, 0)
    }

    func testFilterAndRankSortOrder() {
        struct Item {
            let id: String
            let name: String
        }

        let items = [
            Item(id: "1", name: "super-fast-node"),
            Item(id: "2", name: "node"),
            Item(id: "3", name: "nodejs-runtime"),
            Item(id: "4", name: "python")
        ]

        let ranked = BrewStoreFuzzySearchEngine.filterAndRank(items: items, query: "node") { item in
            [item.name]
        }

        XCTAssertEqual(ranked.count, 3)
        XCTAssertEqual(ranked[0].name, "node", "Exact match must rank first")
        XCTAssertEqual(ranked[1].name, "nodejs-runtime", "Prefix match must rank ahead of substring match")
    }
}
