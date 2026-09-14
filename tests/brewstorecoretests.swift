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

    @MainActor
    func testDeclutteringAndHidingPreferences() {
        let prefs = BrewStorePreferences.shared

        // Test toggling and defaults
        prefs.hideCompletedBundles = true
        prefs.hideInstalledWishlist = true
        prefs.hideIdenticalSnapshots = true

        XCTAssertTrue(prefs.hideCompletedBundles)
        XCTAssertTrue(prefs.hideInstalledWishlist)
        XCTAssertTrue(prefs.hideIdenticalSnapshots)

        prefs.resetToDefaults()

        XCTAssertFalse(prefs.hideCompletedBundles)
        XCTAssertFalse(prefs.hideInstalledWishlist)
        XCTAssertFalse(prefs.hideIdenticalSnapshots)
    }

    func testStack100PercentCompletionDetection() {
        let stack = BrewStoreStack(
            id: "test-stack",
            name: "Test Developer Suite",
            description: "A test bundle",
            icon: "shippingbox",
            bundleType: .hybrid,
            pricingTier: .freeFOSS,
            formulae: ["git", "node"],
            casks: ["ghostty"],
            isCustom: false
        )

        let partiallyInstalled = [
            BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.40.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "ghostty", name: "ghostty", description: "", homepage: "", version: "1.0.0", kind: .cask, isInstalled: true)
        ]

        XCTAssertEqual(stack.installedCount(in: partiallyInstalled), 2)
        XCTAssertFalse(stack.isFullyInstalled(in: partiallyInstalled))
        XCTAssertEqual(stack.missingPackages(in: partiallyInstalled).formulae, ["node"])
        XCTAssertTrue(stack.missingPackages(in: partiallyInstalled).casks.isEmpty)

        let fullyInstalled = [
            BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.40.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "node", name: "node", description: "", homepage: "", version: "20.0.0", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "ghostty", name: "ghostty", description: "", homepage: "", version: "1.0.0", kind: .cask, isInstalled: true)
        ]

        XCTAssertEqual(stack.installedCount(in: fullyInstalled), 3)
        XCTAssertTrue(stack.isFullyInstalled(in: fullyInstalled))
        XCTAssertTrue(stack.missingPackages(in: fullyInstalled).formulae.isEmpty)
        XCTAssertTrue(stack.missingPackages(in: fullyInstalled).casks.isEmpty)
    }

    @MainActor
    func testSnapshotInSyncDiffComputation() {
        let snapshotManager = BrewStoreSnapshotManager()
        let url = URL(fileURLWithPath: "/tmp/snapshot_test.json")
        let snapshot = BrewStoreSnapshot(
            id: "test-snapshot",
            timestamp: Date(),
            name: "Test Snapshot",
            fileURL: url,
            formulae: ["zsh", "tmux"],
            casks: ["docker"],
            taps: ["homebrew/core"]
        )

        let matchingPackages = [
            BrewStorePackage(id: "zsh", name: "zsh", description: "", homepage: "", version: "5.9", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "tmux", name: "tmux", description: "", homepage: "", version: "3.3a", kind: .formula, isInstalled: true),
            BrewStorePackage(id: "docker", name: "docker", description: "", homepage: "", version: "4.0", kind: .cask, isInstalled: true)
        ]
        let matchingTaps = [BrewStoreTap(id: "homebrew/core", name: "homebrew/core")]

        let inSyncDiff = snapshotManager.computeDiff(for: snapshot, currentPackages: matchingPackages, currentTaps: matchingTaps)
        XCTAssertFalse(inSyncDiff.hasDifferences)
        XCTAssertEqual(inSyncDiff.totalChanges, 0)
        XCTAssertEqual(inSyncDiff.identicalCount, 3)

        // Adding an extra package should produce differences
        let alteredPackages = matchingPackages + [
            BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "", homepage: "", version: "14.0", kind: .formula, isInstalled: true)
        ]
        let differingDiff = snapshotManager.computeDiff(for: snapshot, currentPackages: alteredPackages, currentTaps: matchingTaps)
        XCTAssertTrue(differingDiff.hasDifferences)
        XCTAssertEqual(differingDiff.totalChanges, 1)
        XCTAssertEqual(differingDiff.addedFormulae, ["ripgrep"])
    }

    @MainActor
    func testDiscoveryCatalogFindItem() {
        let catalog = BrewStoreDiscoveryCatalog.shared
        let pkg = BrewStorePackage(
            id: "test-cask",
            name: "Test Cask",
            description: "A test description",
            homepage: "https://example.com",
            version: "2.0.0",
            kind: .cask,
            isInstalled: true,
            isOutdated: false
        )
        catalog.mergeLocalPackages([pkg])
        let found = catalog.findItem(id: "test-cask")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, "test-cask")
    }
}
