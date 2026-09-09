@testable import BrewStore
import XCTest

final class BrewStoreCoreTests: XCTestCase {
    func testCommandExecutorRejectsRelativeExecutable() {
        let result = BrewStoreCommandExecutor.shared.run(executablePath: "brew")

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.launchErrorDescription, "The executable path must be absolute.")
    }

    func testCommandExecutorCapturesOutput() {
        let result = BrewStoreCommandExecutor.shared.run(
            executablePath: "/bin/echo",
            arguments: ["BrewStore test"]
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.standardOutput, "BrewStore test\n")
        XCTAssertFalse(result.standardOutputWasTruncated)
    }

    func testCommandExecutorHandlesTimeoutSafely() {
        let result = BrewStoreCommandExecutor.shared.run(
            executablePath: "/bin/sleep",
            arguments: ["5"],
            timeout: 0.1,
            category: .readOnly
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.didTimeOut)
        XCTAssertTrue(result.wasTerminated)
    }

    func testFastCacheEngineSaveAndLoad() {
        let pkg = BrewStorePackage(
            id: "test-pkg",
            name: "Test Package",
            description: "A test package",
            homepage: "https://example.com",
            version: "1.0.0",
            kind: .formula,
            isInstalled: true,
            isOutdated: false,
            installedVersion: "1.0.0"
        )
        BrewStoreFastCacheEngine.saveCache(packages: [pkg], taps: [], services: [], force: true)

        let expectation = XCTestExpectation(description: "Cache save completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let loaded = BrewStoreFastCacheEngine.loadCacheSynchronously()
            XCTAssertNotNil(loaded)
            XCTAssertEqual(loaded?.packages.first?.id, "test-pkg")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testHomebrewManagerStaticDetection() {
        let path = HomebrewManager.detectBrewPath()
        if let path {
            XCTAssertTrue(path.hasPrefix("/"))
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
            let prefix = HomebrewManager.detectBrewPrefix()
            XCTAssertNotNil(prefix)
            XCTAssertTrue(prefix!.hasPrefix("/"))
        }
    }

    func testPackageInstallAnalyticsFormattingAndParsing() {
        let sampleJSON = Data("""
        {
            "analytics": {
                "install": {
                    "30d": {
                        "wget": 125000
                    },
                    "90d": {
                        "wget": 360000
                    },
                    "365d": {
                        "wget": 1500000
                    }
                },
                "install_on_request": {
                    "30d": {
                        "wget": 110000
                    }
                }
            }
        }
        """.utf8)

        let analytics = BrewStoreAnalyticsManager.parseJSON(data: sampleJSON, packageID: "wget", kind: .formula)
        XCTAssertNotNil(analytics)
        XCTAssertEqual(analytics?.install30d, 125000)
        XCTAssertEqual(analytics?.install90d, 360000)
        XCTAssertEqual(analytics?.install365d, 1500000)
        XCTAssertEqual(analytics?.formatted30d, "125.0K")
        XCTAssertEqual(analytics?.formatted365d, "1.5M")
        XCTAssertGreaterThan(analytics?.install7d ?? 0, 0)
    }

    func testPackageInstallAnalyticsFallbackDecoding() throws {
        let json = Data("""
        {
            "packageID": "visual-studio-code",
            "install30d": 45000,
            "install90d": 120000,
            "install365d": 500000
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(PackageInstallAnalytics.self, from: json)
        XCTAssertEqual(decoded.install7d, Int(round(45000.0 * 7.0 / 30.0)))
        XCTAssertEqual(decoded.formatted7d, "10.5K")
        XCTAssertEqual(decoded.formatted30d, "45.0K")
        XCTAssertEqual(decoded.formatted365d, "500.0K")
    }
}
