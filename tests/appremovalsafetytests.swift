@testable import BrewStore
import XCTest

final class AppRemovalSafetyTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/private/tmp")

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/private/tmp/BrewStoreRemovalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testValidatorRejectsOutsideAndProtectedPaths() throws {
        let allowed = root.appendingPathComponent("allowed")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside)
        let validator = BrewStorePathSafetyValidator(allowedRoots: [allowed])

        XCTAssertThrowsError(try validator.validate(outside)) { error in
            XCTAssertEqual(error as? BrewStorePathSafetyError, .outsideAllowedRoots(outside))
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertThrowsError(try validator.validate(home)) { error in
            XCTAssertEqual(error as? BrewStorePathSafetyError, .protectedPath(home))
        }
    }

    func testValidatorRejectsSymlinkTargets() throws {
        let allowed = root.appendingPathComponent("allowed")
        let outside = root.appendingPathComponent("outside")
        let link = allowed.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let validator = BrewStorePathSafetyValidator(allowedRoots: [allowed])

        XCTAssertThrowsError(try validator.validate(link)) { error in
            XCTAssertEqual(error as? BrewStorePathSafetyError, .symbolicLink(link))
        }
    }

    func testScannerRejectsFalsePositiveMatchesAndSkipsSymlinks() throws {
        let home = root.appendingPathComponent("home")
        let support = home.appendingPathComponent("Library/Application Support")
        let cache = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let exactName = support.appendingPathComponent("Example")
        let exactBundle = cache.appendingPathComponent("com.example.app")
        let groupContainer = support.appendingPathComponent("group.com.example.app")
        let falseName = support.appendingPathComponent("Example Notes")
        let falseBundle = support.appendingPathComponent("com.example.application")
        let outside = root.appendingPathComponent("outside")
        let symlink = support.appendingPathComponent("Example.app")
        for url in [exactName, exactBundle, groupContainer, falseName, falseBundle, outside] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        let applicationURL = root.appendingPathComponent("Applications/Example.app")
        try FileManager.default.createDirectory(at: applicationURL, withIntermediateDirectories: true)
        let identity = BrewStoreAppIdentity(name: "Example", bundleIdentifier: "com.example.app", applicationURL: applicationURL)
        let plan = BrewStoreAppRemovalScanner().scan(application: identity, homeDirectory: home)
        let paths = Set(plan.candidates.map(\.url.lastPathComponent))

        XCTAssertEqual(paths, Set(["Example.app", "Example", "com.example.app", "group.com.example.app"]))
        XCTAssertFalse(paths.contains("Example Notes"))
        XCTAssertFalse(paths.contains("com.example.application"))
    }

    func testTrashExecutorReportsCancellationAfterMovedItems() throws {
        let allowed = root.appendingPathComponent("allowed")
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        let first = allowed.appendingPathComponent("first")
        let second = allowed.appendingPathComponent("second")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let plan = makePlan(candidates: [first, second])
        let validator = BrewStorePathSafetyValidator(allowedRoots: [allowed])
        var moved: [URL] = []
        var checks = 0
        let executor = BrewStoreTrashExecutor(fileManager: .default, validator: validator) { url in moved.append(url) }

        let result = executor.execute(plan: plan) {
            checks += 1
            return checks > 1
        }

        guard case let .cancelled(manifest) = result else { return XCTFail("Expected cancellation") }
        XCTAssertEqual(manifest.movedURLs, [first])
        XCTAssertEqual(moved, [first])
        XCTAssertTrue(manifest.failures.isEmpty)
    }

    func testTrashExecutorReportsPartialFailure() throws {
        let allowed = root.appendingPathComponent("allowed")
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try Data("good".utf8).write(to: allowed.appendingPathComponent("good"))
        try Data("bad".utf8).write(to: outside)
        let good = allowed.appendingPathComponent("good")
        let plan = makePlan(candidates: [good, outside])
        let validator = BrewStorePathSafetyValidator(allowedRoots: [allowed])
        var moved: [URL] = []
        let executor = BrewStoreTrashExecutor(fileManager: .default, validator: validator) { url in moved.append(url) }

        let result = executor.execute(plan: plan)

        guard case let .partiallyCompleted(manifest) = result else { return XCTFail("Expected partial completion") }
        XCTAssertEqual(manifest.movedURLs, [good])
        XCTAssertEqual(moved, [good])
        XCTAssertEqual(manifest.failures.map(\.url), [outside])
    }

    private func makePlan(candidates: [URL]) -> BrewStoreRemovalPlan {
        BrewStoreRemovalPlan(
            application: BrewStoreAppIdentity(name: "Example", bundleIdentifier: "com.example.app", applicationURL: root.appendingPathComponent("Example.app")),
            candidates: candidates.map { BrewStoreRemovalCandidate(url: $0, kind: .applicationSupport, size: 1, confidence: .exactApplicationName) }
        )
    }
}
