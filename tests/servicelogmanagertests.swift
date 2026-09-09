@testable import BrewStore
import XCTest

final class ServiceLogManagerTests: XCTestCase {
    func testCandidateLogPaths() {
        let paths = BrewStoreServiceLogManager.candidateLogPaths(for: "postgresql@17", prefix: "/opt/homebrew")
        XCTAssertFalse(paths.isEmpty)
        XCTAssertTrue(paths.contains("/opt/homebrew/var/log/postgresql@17.log"))
        XCTAssertTrue(paths.contains("/opt/homebrew/var/log/postgresql.log"))
    }

    @MainActor
    func testStreamingLifecycle() {
        let manager = HomebrewManager()
        let logManager = BrewStoreServiceLogManager.shared

        logManager.startStreaming(serviceName: "nonexistent_service_test", manager: manager)
        XCTAssertTrue(logManager.isStreaming)
        XCTAssertEqual(logManager.activeServiceName, "nonexistent_service_test")
        XCTAssertFalse(logManager.logEntries.isEmpty)

        logManager.stopStreaming()
        XCTAssertFalse(logManager.isStreaming)
    }
}
