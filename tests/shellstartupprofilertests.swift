import XCTest
@testable import BrewStore

final class ShellStartupProfilerTests: XCTestCase {

    func testGradeEvaluation() {
        XCTAssertEqual(ShellPerformanceGrade.evaluate(latencyMs: 45.0), .gradeA)
        XCTAssertEqual(ShellPerformanceGrade.evaluate(latencyMs: 99.9), .gradeA)
        XCTAssertEqual(ShellPerformanceGrade.evaluate(latencyMs: 150.0), .gradeB)
        XCTAssertEqual(ShellPerformanceGrade.evaluate(latencyMs: 249.0), .gradeB)
        XCTAssertEqual(ShellPerformanceGrade.evaluate(latencyMs: 350.0), .gradeC)
        XCTAssertEqual(ShellPerformanceGrade.evaluate(latencyMs: 599.0), .gradeC)
        XCTAssertEqual(ShellPerformanceGrade.evaluate(latencyMs: 650.0), .gradeD)
        XCTAssertEqual(ShellPerformanceGrade.evaluate(latencyMs: 1200.0), .gradeD)
    }

    func testStaticSnippetGenerationBashAndZsh() {
        let snippet = ShellStartupProfiler.generateStaticShellenvSnippet(prefix: "/opt/homebrew", shellName: "zsh")
        XCTAssertTrue(snippet.contains("export HOMEBREW_PREFIX=\"/opt/homebrew\""))
        XCTAssertTrue(snippet.contains("export HOMEBREW_CELLAR=\"/opt/homebrew/Cellar\""))
        XCTAssertTrue(snippet.contains("export PATH=\"/opt/homebrew/bin:/opt/homebrew/sbin:$PATH\""))
    }

    func testStaticSnippetGenerationFish() {
        let snippet = ShellStartupProfiler.generateStaticShellenvSnippet(prefix: "/opt/homebrew", shellName: "fish")
        XCTAssertTrue(snippet.contains("set -gx HOMEBREW_PREFIX \"/opt/homebrew\""))
        XCTAssertTrue(snippet.contains("fish_add_path \"/opt/homebrew/bin\""))
    }

    func testMeasureCommandLatencyWithEcho() {
        let latency = ShellStartupProfiler.measureCommandLatency(
            executable: "/bin/echo",
            arguments: ["test"],
            runs: 2
        )
        XCTAssertGreaterThan(latency, 0.0)
        XCTAssertLessThan(latency, 1000.0)
    }

    func testResultFormatting() {
        let result = ShellBenchmarkResult(
            id: "test-id",
            timestamp: Date(),
            shellName: "zsh",
            shellPath: "/bin/zsh",
            totalStartupLatencyMs: 124.6,
            cleanShellLatencyMs: 42.1,
            userConfigOverheadMs: 82.5,
            grade: .gradeB,
            segments: [],
            tips: [],
            cachedShellenvSnippet: "export PATH=..."
        )

        XCTAssertEqual(result.formattedTotalLatency, "124.6 ms")
        XCTAssertEqual(result.formattedOverhead, "+82.5 ms overhead")
        XCTAssertEqual(result.grade.badgeColor, "blue")
    }
}
