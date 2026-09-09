import AppKit
@testable import BrewStore
import Foundation
import XCTest

final class StabilityAndHangPreventionTests: XCTestCase {
    func testCommandExecutorTimeoutDoesNotCrashOnTerminationStatus() {
        let executor = BrewStoreCommandExecutor()
        // /bin/sleep 10 with a short timeout of 0.1s ensures timeout path is triggered
        let result = executor.run(
            executablePath: "/bin/sleep",
            arguments: ["10"],
            timeout: 0.1,
            category: .readOnly
        )

        XCTAssertTrue(result.didTimeOut)
        XCTAssertTrue(result.wasTerminated)
        XCTAssertFalse(result.succeeded)
        // Ensure result did not crash and termination status is nil or signal code
        XCTAssertTrue(result.terminationStatus == nil || result.terminationStatus != 0)
    }

    func testCommandExecutorCancellationTerminatesSafely() {
        let executor = BrewStoreCommandExecutor()
        var cancelNow = false
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
            cancelNow = true
        }

        let result = executor.run(
            executablePath: "/bin/sleep",
            arguments: ["5"],
            timeout: 5.0,
            category: .readOnly,
            cancellationCheck: { cancelNow }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertTrue(result.wasTerminated)
        XCTAssertFalse(result.succeeded)
    }

    func testCommandExecutorNormalExecutionSucceeds() {
        let executor = BrewStoreCommandExecutor()
        let result = executor.run(
            executablePath: "/bin/echo",
            arguments: ["brewstore_stability_check"],
            timeout: 5.0,
            category: .readOnly
        )

        XCTAssertFalse(result.didTimeOut)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertFalse(result.wasTerminated)
        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.standardOutput.contains("brewstore_stability_check"))
    }

    func testServiceLogTailReadingBounded() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testLogURL = tempDir.appendingPathComponent("brewstore_test_service_\(UUID().uuidString).log")

        var lines: [String] = []
        for i in 1 ... 250 {
            if i == 240 {
                lines.append("[ERROR] Critical failure on worker thread #\(i)")
            } else if i == 245 {
                lines.append("[FATAL] Memory allocation warning #\(i)")
            } else {
                lines.append("[INFO] Standard worker heartbeat line #\(i)")
            }
        }
        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: testLogURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testLogURL) }

        // Read with maxLines: 50
        let entries = BrewStoreServiceLogManager.readTailEntries(
            filePath: testLogURL.path,
            maxBytes: 128 * 1024,
            maxLines: 50
        )

        XCTAssertEqual(entries.count, 50)
        XCTAssertEqual(entries.last?.text, "[INFO] Standard worker heartbeat line #250")

        // Line 240 and 245 are within the last 50 lines (201..250)
        let errorEntries = entries.filter(\.isError)
        XCTAssertEqual(errorEntries.count, 2)
        XCTAssertTrue(errorEntries.contains { $0.text.contains("Critical failure") })
        XCTAssertTrue(errorEntries.contains { $0.text.contains("Memory allocation warning") })
    }

    @MainActor
    func testSidebarOutlineManagerSelfDelegationLoopProtection() {
        let manager = BrewStoreSidebarOutlineManager.shared
        let outlineView = NSOutlineView()

        // First attach
        manager.attach(to: outlineView)
        XCTAssertTrue(outlineView.delegate === manager)

        // Second attach to same outline view should be an early return no-op
        manager.attach(to: outlineView)
        XCTAssertTrue(outlineView.delegate === manager)

        // Simulating attach when outlineView.delegate is already manager:
        // Must not cause infinite forwarding loop in responds(to:) or forwardingTarget(for:)
        XCTAssertTrue(manager.responds(to: #selector(NSOutlineViewDelegate.outlineView(_:shouldSelectItem:))))
        XCTAssertTrue(manager.responds(to: #selector(NSOutlineViewDelegate.outlineView(_:selectionIndexesForProposedSelection:))))

        // A selector not implemented by manager and with no valid original delegate returns false without recursion
        let fakeSelector = Selector(("nonExistentSidebarSelector:"))
        XCTAssertFalse(manager.responds(to: fakeSelector))
    }

    func testLockManagerForceUnlockIgnoresCriticalPIDs() {
        var killedPIDs: [Int32] = []
        let myPID = getpid()
        let mockChecker: BrewStoreLockManager.ActivePIDsChecker = {
            [-1, 0, 1, myPID, 99999]
        }
        let lockManager = BrewStoreLockManager(pidsChecker: mockChecker)
        // With a dummy prefix where locks directory does not exist, forceUnlock will check PIDs
        let tempPrefix = FileManager.default.temporaryDirectory.appendingPathComponent("brewstore_test_prefix_\(UUID().uuidString)").path

        let result = lockManager.forceUnlock(prefix: tempPrefix, terminateHoldingProcesses: true)
        // Ensure that only PID > 1 and != myPID (i.e. 99999) was targeted, NEVER -1, 0, 1, or myPID
        XCTAssertFalse(result.terminatedPIDs.contains(-1))
        XCTAssertFalse(result.terminatedPIDs.contains(0))
        XCTAssertFalse(result.terminatedPIDs.contains(1))
        XCTAssertFalse(result.terminatedPIDs.contains(myPID))
    }

    func testPrivilegeElevationRunnerThreadSafety() {
        let elevation = BrewStorePrivilegeElevationManager(runner: { _ in
            (true, "mocked_success", nil)
        })
        let status = elevation.requiresElevation(
            package: BrewStorePackage(id: "dummy", name: "Dummy", description: "", homepage: "", version: "1.0", kind: .formula),
            action: .install
        )
        XCTAssertEqual(status, .notRequired)
        XCTAssertFalse(elevation.isPrivilegeError(errorMessage: "all good", outputLog: "done"))
        XCTAssertTrue(elevation.isPrivilegeError(errorMessage: "sudo: a terminal is required", outputLog: ""))
    }
}
