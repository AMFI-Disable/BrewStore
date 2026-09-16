@testable import BrewStore
import CryptoKit
import XCTest

@MainActor
final class FastCacheEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BrewStoreFastCacheEngine.clearCache()
    }

    override func tearDown() {
        BrewStoreFastCacheEngine.clearCache()
        super.tearDown()
    }

    func testFastCacheHeaderPropertiesAndCodable() throws {
        let now = Date()
        let header = FastCacheHeader(
            timestamp: now,
            version: "1.0.0",
            sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            packageCount: 150,
            installedCount: 42,
            outdatedCount: 3,
            tapCount: 5,
            serviceCount: 8
        )

        let data = try JSONEncoder().encode(header)
        let decoded = try JSONDecoder().decode(FastCacheHeader.self, from: data)

        XCTAssertEqual(decoded.version, "1.0.0")
        XCTAssertEqual(decoded.sha256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(decoded.packageCount, 150)
        XCTAssertEqual(decoded.installedCount, 42)
        XCTAssertEqual(decoded.outdatedCount, 3)
        XCTAssertEqual(decoded.tapCount, 5)
        XCTAssertEqual(decoded.serviceCount, 8)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testMicroHeaderPersistenceAndFreshnessCheck() async {
        let pkg = BrewStorePackage(
            id: "wget",
            name: "wget",
            description: "Internet file retriever",
            homepage: "https://www.gnu.org/software/wget/",
            version: "1.24.5",
            kind: .formula,
            isInstalled: true,
            isOutdated: false,
            installedVersion: "1.24.5"
        )

        let tap = BrewStoreTap(id: "homebrew/core", name: "homebrew/core")
        let service = BrewStoreService(id: "nginx", name: "nginx", status: "started", user: "staff", file: "/tmp/nginx.plist")

        BrewStoreFastCacheEngine.saveCache(packages: [pkg], taps: [tap], services: [service], force: true)

        var attempts = 0
        while BrewStoreFastCacheEngine.loadHeaderSynchronously() == nil, attempts < 30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        guard let header = BrewStoreFastCacheEngine.loadHeaderSynchronously() else {
            XCTFail("Micro-header was not written to disk")
            return
        }

        XCTAssertEqual(header.packageCount, 1)
        XCTAssertEqual(header.installedCount, 1)
        XCTAssertEqual(header.outdatedCount, 0)
        XCTAssertEqual(header.tapCount, 1)
        XCTAssertEqual(header.serviceCount, 1)
        XCTAssertFalse(header.sha256.isEmpty)

        // Freshness verification
        XCTAssertTrue(BrewStoreFastCacheEngine.isCatalogCacheFresh(prefix: nil, maxAgeSeconds: 3600))
        XCTAssertFalse(BrewStoreFastCacheEngine.isCatalogCacheFresh(prefix: nil, maxAgeSeconds: -1))
    }

    func testClearCacheRemovesBothPayloadAndHeaderFiles() async {
        let pkg = BrewStorePackage(
            id: "curl",
            name: "curl",
            description: "Command line tool for transferring data with URLs",
            homepage: "https://curl.se",
            version: "8.7.1",
            kind: .formula
        )

        BrewStoreFastCacheEngine.saveCache(packages: [pkg], taps: [], services: [], force: true)

        var attempts = 0
        while BrewStoreFastCacheEngine.loadHeaderSynchronously() == nil, attempts < 30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: BrewStoreFastCacheEngine.cacheFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: BrewStoreFastCacheEngine.cacheHeaderURL.path))

        BrewStoreFastCacheEngine.clearCache()

        XCTAssertFalse(FileManager.default.fileExists(atPath: BrewStoreFastCacheEngine.cacheFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: BrewStoreFastCacheEngine.cacheHeaderURL.path))
    }

    func testHomebrewManagerBackgroundSyncStateTransition() async {
        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, args, _, category, _, _, _ in
            if args.contains("list"), args.contains("--cask") {
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: "",
                    terminationStatus: 0,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }
            if args.contains("list"), args.contains("--formula") {
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: "",
                    terminationStatus: 0,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }
            if args.contains("list"), args.contains("--pinned") {
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: "",
                    terminationStatus: 0,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }
            if args.contains("outdated") {
                return BrewStoreCommandResult(
                    standardOutput: "{\"formulae\":[],\"casks\":[]}",
                    standardError: "",
                    terminationStatus: 0,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }
            if args.contains("info"), args.contains("--cask") {
                return BrewStoreCommandResult(
                    standardOutput: "[]",
                    standardError: "",
                    terminationStatus: 0,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }
            if args.contains("info"), args.contains("--formula") {
                return BrewStoreCommandResult(
                    standardOutput: "[]",
                    standardError: "",
                    terminationStatus: 0,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }
            if args.contains("services") {
                return BrewStoreCommandResult(
                    standardOutput: "[]",
                    standardError: "",
                    terminationStatus: 0,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }
            if args.contains("tap") {
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: "",
                    terminationStatus: 0,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }
            return BrewStoreCommandResult(
                standardOutput: "",
                standardError: "",
                terminationStatus: 0,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: category,
                launchErrorDescription: nil
            )
        }

        let executor = BrewStoreCommandExecutor(customHandler: mockHandler)
        let manager = HomebrewManager(executor: executor)

        // Seed with a cached package so manager considers this a background delta sync
        manager.packages = [
            BrewStorePackage(
                id: "test",
                name: "test",
                description: "",
                homepage: "",
                version: "1.0",
                kind: .formula
            )
        ]

        XCTAssertFalse(manager.isBackgroundSyncing)
        manager.refresh()

        XCTAssertTrue(manager.isLoading)
        XCTAssertTrue(manager.isBackgroundSyncing)

        var attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(manager.isLoading)
        XCTAssertFalse(manager.isBackgroundSyncing)
    }

    func testFastCacheEngineAutoPurgesCorruptCacheOnDisk() throws {
        let dir = BrewStoreFastCacheEngine.cacheDirectoryURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let corruptData = Data("corrupted invalid json content".utf8)
        try corruptData.write(to: BrewStoreFastCacheEngine.cacheFileURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: BrewStoreFastCacheEngine.cacheFileURL.path))

        let loaded = BrewStoreFastCacheEngine.loadCacheSynchronously()
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: BrewStoreFastCacheEngine.cacheFileURL.path), "Corrupted cache file must be automatically removed from disk")
    }
}
