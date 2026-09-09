@testable import BrewStore
import XCTest

final class SpeedTestManagerTests: XCTestCase {
    @MainActor
    func testSpeedTestManagerInitializationAndDefaults() {
        let manager = BrewStoreSpeedTestManager.shared

        XCTAssertTrue(manager.isPeriodicEnabled)
        XCTAssertGreaterThanOrEqual(manager.intervalSeconds, 5)
        XCTAssertLessThanOrEqual(manager.intervalSeconds, 3600)
    }

    @MainActor
    func testSpeedTestIntervalClamping() {
        let manager = BrewStoreSpeedTestManager.shared

        manager.intervalSeconds = 15
        XCTAssertEqual(manager.intervalSeconds, 15)

        // Clamping minimum to 5
        manager.intervalSeconds = 2
        XCTAssertEqual(manager.intervalSeconds, 5)

        // Clamping maximum to 3600
        manager.intervalSeconds = 10000
        XCTAssertEqual(manager.intervalSeconds, 3600)

        // Restore to 15
        manager.intervalSeconds = 15
        XCTAssertEqual(manager.intervalSeconds, 15)
    }

    @MainActor
    func testSpeedTestJSONParsingAndFormattedSpeed() {
        let manager = BrewStoreSpeedTestManager.shared

        // Set simulated measured speed: 15 MB/s = 15,000,000 bytes/sec
        manager.lastMeasuredSpeedBytesPerSec = 15_000_000
        manager.lastMeasuredLatencyMs = 20.0
        manager.lastMeasuredAt = Date()

        XCTAssertEqual(manager.currentDownloadSpeedMBps, 15.0)
        XCTAssertEqual(manager.currentDownloadSpeedMbps, 120.0)
        XCTAssertTrue(manager.formattedSpeed.contains("15.0 MB/s"))
        XCTAssertTrue(manager.formattedSpeed.contains("120.0 Mbps"))
        XCTAssertEqual(manager.formattedLatency, "20 ms")
    }

    @MainActor
    func testUpdateEstimatorWithSpeedTestIntegration() {
        let manager = BrewStoreSpeedTestManager.shared

        let testPkg = BrewStorePackage(
            id: "test-tool",
            name: "Test Tool",
            description: "Test description",
            homepage: "https://example.com",
            version: "1.0.0",
            kind: .formula,
            isInstalled: false,
            isOutdated: false,
            dependencies: [],
            caveats: nil,
            installedVersion: nil
        )

        // With high speed (e.g. 100 MB/s)
        manager.lastMeasuredSpeedBytesPerSec = 100_000_000
        let fastEstimate = BrewStoreUpdateEstimator.estimate(for: testPkg)
        XCTAssertGreaterThan(fastEstimate.totalSeconds, 0)

        // With slow speed (e.g. 1 MB/s)
        manager.lastMeasuredSpeedBytesPerSec = 1_000_000
        let slowEstimate = BrewStoreUpdateEstimator.estimate(for: testPkg)
        XCTAssertGreaterThan(slowEstimate.totalSeconds, 0)
        XCTAssertGreaterThan(slowEstimate.totalSeconds, fastEstimate.totalSeconds)
    }
}
