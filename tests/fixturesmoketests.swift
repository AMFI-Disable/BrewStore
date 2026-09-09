@testable import BrewStore
import Foundation
import XCTest

final class FixtureSmokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BrewStoreFixtureMode.setOverrideActive(true)
    }

    override func tearDown() {
        BrewStoreFixtureMode.cleanupFixtureEnvironment()
        BrewStoreFixtureMode.setOverrideActive(false)
        super.tearDown()
    }

    // MARK: - Uninstall Workflows

    @MainActor
    func testSinglePackageUninstallSuccessInFixtureMode() async {
        let manager = HomebrewManager()
        let testPkg = BrewStorePackage(
            id: "fixture-sample-tool",
            name: "fixture-sample-tool",
            description: "Disposable test fixture package",
            homepage: "https://brewstore.test",
            version: "1.0.0",
            kind: .formula,
            installedVersion: "1.0.0"
        )
        manager.packages = [testPkg]

        let didSucceed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            manager.perform(package: testPkg, action: .uninstall) { success in
                continuation.resume(returning: success)
            }
        }

        XCTAssertTrue(didSucceed)
        XCTAssertNil(manager.errorMessage)
        XCTAssertTrue(manager.statusMessage.contains("Ready") || manager.statusMessage.contains("completed") || manager.outputLog.contains("Successfully uninstalled"))
    }

    @MainActor
    func testSinglePackageUninstallFailureSimulationInFixtureMode() async {
        let manager = HomebrewManager()
        let failingPkg = BrewStorePackage(
            id: "fixture-fail-package",
            name: "fixture-fail-package",
            description: "Failing test fixture package",
            homepage: "https://brewstore.test",
            version: "1.0.0",
            kind: .formula,
            installedVersion: "1.0.0"
        )
        manager.packages = [failingPkg]

        let didSucceed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            manager.perform(package: failingPkg, action: .uninstall) { success in
                continuation.resume(returning: success)
            }
        }

        XCTAssertFalse(didSucceed)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertTrue(manager.errorMessage?.contains("simulated") == true || manager.errorMessage?.contains("Refusing") == true)
    }

    @MainActor
    func testBatchUninstallPartialFailureInFixtureMode() async {
        let manager = HomebrewManager()
        let goodPkg = BrewStorePackage(
            id: "fixture-good-tool",
            name: "fixture-good-tool",
            description: "Healthy tool",
            homepage: "",
            version: "1.0",
            kind: .formula,
            installedVersion: "1.0"
        )
        let badPkg = BrewStorePackage(
            id: "fixture-fail-tool",
            name: "fixture-fail-tool",
            description: "Broken tool",
            homepage: "",
            version: "1.0",
            kind: .formula,
            installedVersion: "1.0"
        )
        manager.packages = [goodPkg, badPkg]

        let batchResults = await withCheckedContinuation { (continuation: CheckedContinuation<[String: Bool], Never>) in
            manager.batchPerform(packages: [goodPkg, badPkg], action: .uninstall) { results in
                continuation.resume(returning: results)
            }
        }

        XCTAssertEqual(batchResults[goodPkg.id], true)
        XCTAssertEqual(batchResults[badPkg.id], false)
    }

    @MainActor
    func testAutoremoveInFixtureMode() async {
        let manager = HomebrewManager()
        manager.autoremove()

        // Wait a small runloop turn for background task to finish
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(manager.errorMessage)
        XCTAssertTrue(manager.outputLog.contains("Autoremoved") || manager.statusMessage.contains("Ready"))
    }

    // MARK: - Snapshot Restore and Deletion Workflows

    @MainActor
    func testDisposableSnapshotSeedingAndDeletion() {
        let snapshotManager = BrewStoreSnapshotManager()
        let initialCount = snapshotManager.snapshots.count
        XCTAssertGreaterThanOrEqual(initialCount, 2, "Disposable fixture mode should seed initial snapshots.")

        guard let firstSnapshot = snapshotManager.snapshots.first else {
            XCTFail("No snapshot found to test deletion")
            return
        }

        // Verify the file is in NSTemporaryDirectory
        XCTAssertTrue(firstSnapshot.fileURL.path.contains(NSTemporaryDirectory()))

        // Test deletion
        snapshotManager.deleteSnapshot(firstSnapshot)
        XCTAssertEqual(snapshotManager.snapshots.count, initialCount - 1)
        XCTAssertFalse(snapshotManager.snapshots.contains { $0.id == firstSnapshot.id })
    }

    @MainActor
    func testSnapshotRollbackPlanAndExecutionInFixtureMode() async {
        let snapshotManager = BrewStoreSnapshotManager()
        guard let snapshot = snapshotManager.snapshots.first else {
            XCTFail("Missing seeded fixture snapshot")
            return
        }

        let manager = HomebrewManager()
        let installedPkg = BrewStorePackage(
            id: "temporary-extra-pkg",
            name: "temporary-extra-pkg",
            description: "Package installed after snapshot",
            homepage: "",
            version: "1.0",
            kind: .formula,
            isInstalled: true,
            installedVersion: "1.0"
        )
        manager.packages = [installedPkg]

        let rollbackManager = BrewStoreSnapshotRollbackManager.shared
        let plan = rollbackManager.computePlan(currentPackages: manager.packages, snapshot: snapshot)

        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.packagesToUninstall.contains("temporary-extra-pkg"))

        let rollbackTask = Task { @MainActor in
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                rollbackManager.executeRollback(plan: plan, manager: manager) { success in
                    continuation.resume(returning: success)
                }
            }
        }

        // Wait for preview request to be posted
        let previewDeadline = Date().addingTimeInterval(2.0)
        while BrewStoreUninstallCoordinator.shared.pendingRequest == nil, Date() < previewDeadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // Confirm the preview request
        XCTAssertNotNil(BrewStoreUninstallCoordinator.shared.pendingRequest)
        BrewStoreUninstallCoordinator.shared.confirm()

        let rollbackSucceeded = await rollbackTask.value
        XCTAssertTrue(rollbackSucceeded)
        XCTAssertFalse(rollbackManager.isRollingBack)
        XCTAssertTrue(rollbackManager.statusMessage.contains("Rollback complete"))
    }

    // MARK: - Service Lifecycle Workflows

    @MainActor
    func testServiceStartAndSimulatedFailureInFixtureMode() async {
        let manager = HomebrewManager()
        let goodService = BrewStoreService(
            id: "fixture-nginx",
            name: "fixture-nginx",
            status: "none",
            user: "brewuser",
            file: nil
        )
        let failService = BrewStoreService(
            id: "fixture-fail-postgres",
            name: "fixture-fail-postgres",
            status: "none",
            user: "brewuser",
            file: nil
        )
        manager.services = [goodService, failService]

        // 1. Successful service start
        manager.perform(service: goodService, action: .start)
        let deadline1 = Date().addingTimeInterval(2.0)
        while manager.isOperating, Date() < deadline1 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(manager.operationHistory.first?.succeeded, true)
        XCTAssertTrue(manager.operationHistory.first?.detail.contains("Successfully started") == true)

        // 2. Failing service start
        manager.perform(service: failService, action: .start)
        let deadline2 = Date().addingTimeInterval(2.0)
        while manager.isOperating, Date() < deadline2 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(manager.operationHistory.first?.succeeded, false)
        XCTAssertTrue(manager.operationHistory.first?.detail.contains("failed") == true)
    }

    // MARK: - Tap Lifecycle Workflows

    @MainActor
    func testTapAndUntapInFixtureMode() async {
        let manager = HomebrewManager()

        // 1. Successful tap
        manager.tap(name: "custom/fixture-repo")
        let deadline1 = Date().addingTimeInterval(2.0)
        while manager.isOperating, Date() < deadline1 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(manager.operationHistory.first?.succeeded, true)

        // 2. Failing tap
        manager.tap(name: "invalid/fixture-fail-repo")
        let deadline2 = Date().addingTimeInterval(2.0)
        while manager.isOperating, Date() < deadline2 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(manager.operationHistory.first?.succeeded, false)

        // 3. Successful untap
        manager.untap(name: "custom/fixture-repo")
        let deadline3 = Date().addingTimeInterval(2.0)
        while manager.isOperating, Date() < deadline3 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(manager.operationHistory.first?.succeeded, true)
    }

    // MARK: - Cancellation Handling

    func testCancellationCheckInFixtureMode() {
        let executor = BrewStoreCommandExecutor()
        let result = executor.run(
            executablePath: "/opt/homebrew/bin/brew",
            arguments: ["uninstall", "some-package"],
            timeout: 30,
            category: .destructiveMutation,
            cancellationCheck: { true }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertTrue(result.wasTerminated)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.terminationStatus, 130)
    }
}
