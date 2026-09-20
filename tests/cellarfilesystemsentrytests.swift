import XCTest
@testable import BrewStore

@MainActor
final class CellarFileSystemSentryTests: XCTestCase {

    func testDefaultPathsContainsStandardLocations() {
        let paths = CellarFileSystemSentry.defaultPathsToMonitor
        XCTAssertTrue(paths.contains("/opt/homebrew/Cellar"))
        XCTAssertTrue(paths.contains("/opt/homebrew/Caskroom"))
        XCTAssertTrue(paths.contains("/usr/local/Cellar"))
        XCTAssertTrue(paths.contains("/usr/local/Caskroom"))
    }

    func testStartAndStopMonitoringOnTemporaryDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CellarSentryTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sentry = CellarFileSystemSentry(targetPaths: [tempDir.path], debounceInterval: 0.05)
        XCTAssertFalse(sentry.isMonitoring)

        sentry.startMonitoring()
        XCTAssertTrue(sentry.isMonitoring)
        XCTAssertEqual(sentry.monitoredPaths, [tempDir.path])

        sentry.stopMonitoring()
        XCTAssertFalse(sentry.isMonitoring)
        XCTAssertTrue(sentry.monitoredPaths.isEmpty)
    }

    func testImmediateDriftTrigger() {
        var receivedPath: String?
        let sentry = CellarFileSystemSentry(debounceInterval: 1.0) { path in
            receivedPath = path
        }

        XCTAssertEqual(sentry.driftEventCount, 0)
        XCTAssertNil(sentry.lastDriftDetectedAt)

        sentry.triggerDriftImmediately(path: "/test/path/Cellar")

        XCTAssertEqual(receivedPath, "/test/path/Cellar")
        XCTAssertEqual(sentry.driftEventCount, 1)
        XCTAssertNotNil(sentry.lastDriftDetectedAt)
    }

    func testDebouncedDriftConsolidation() async throws {
        var callbackCount = 0
        let sentry = CellarFileSystemSentry(debounceInterval: 0.05) { _ in
            callbackCount += 1
        }

        // Fire multiple rapid events
        sentry.scheduleDebouncedDrift(from: "/test/Cellar")
        sentry.scheduleDebouncedDrift(from: "/test/Cellar")
        sentry.scheduleDebouncedDrift(from: "/test/Cellar")

        XCTAssertEqual(callbackCount, 0)

        // Wait for debounce window (0.05s) to elapse
        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(sentry.driftEventCount, 1)
        XCTAssertNotNil(sentry.lastDriftDetectedAt)
    }

    func testFileWriteTriggersWatcher() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CellarSentryFS_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let expectation = expectation(description: "Drift detected via FileSystem event")
        let sentry = CellarFileSystemSentry(targetPaths: [tempDir.path], debounceInterval: 0.05) { path in
            if path == tempDir.path {
                expectation.fulfill()
            }
        }

        sentry.startMonitoring()
        XCTAssertTrue(sentry.isMonitoring)

        // Write a test file into the monitored folder
        let sampleFile = tempDir.appendingPathComponent("sample_package")
        try "installed binary".write(to: sampleFile, atomically: true, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertGreaterThanOrEqual(sentry.driftEventCount, 1)

        sentry.stopMonitoring()
    }
}
