@testable import BrewStore
import Darwin
import Foundation
import XCTest

final class BrewStoreLockManagerTests: XCTestCase {
    func testIsFileLockedDetection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let lockPath = tempDir.appendingPathComponent("test.formula.lock").path

        let manager = BrewStoreLockManager(pidsChecker: { [12345] })

        // Initially unlocked
        XCTAssertFalse(manager.isFileLocked(atPath: lockPath))

        // Open and acquire lock
        let fd = open(lockPath, O_RDWR | O_CREAT, 0o644)
        XCTAssertGreaterThanOrEqual(fd, 0)
        let lockResult = flock(fd, LOCK_EX)
        XCTAssertEqual(lockResult, 0)

        // Subprocess or second check from same manager
        XCTAssertTrue(manager.isFileLocked(atPath: lockPath))

        // Release lock
        flock(fd, LOCK_UN)
        close(fd)

        XCTAssertFalse(manager.isFileLocked(atPath: lockPath))

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCheckLockStateWithActiveHoldingPID() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let locksDir = tempDir.appendingPathComponent("var/homebrew/locks")
        try FileManager.default.createDirectory(at: locksDir, withIntermediateDirectories: true)
        let lockPath = locksDir.appendingPathComponent("git.formula.lock").path

        let manager = BrewStoreLockManager(pidsChecker: { [9876] })

        // Before locking
        XCTAssertEqual(manager.checkLockState(prefix: tempDir.path, targetPackage: "git"), .free)

        // Lock file
        let fd = open(lockPath, O_RDWR | O_CREAT, 0o644)
        flock(fd, LOCK_EX)

        let state = manager.checkLockState(prefix: tempDir.path, targetPackage: "git")
        if case let .locked(fileName, pid, msg) = state {
            XCTAssertEqual(fileName, "git.formula.lock")
            XCTAssertEqual(pid, 9876)
            XCTAssertTrue(msg.contains("9876"))
        } else {
            XCTFail("Expected .locked state")
        }

        flock(fd, LOCK_UN)
        close(fd)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWaitForLockReleaseSucceedsWhenLockFreed() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let locksDir = tempDir.appendingPathComponent("var/homebrew/locks")
        try FileManager.default.createDirectory(at: locksDir, withIntermediateDirectories: true)
        let lockPath = locksDir.appendingPathComponent("formula.lock").path

        let manager = BrewStoreLockManager(pidsChecker: { [] })

        let fd = open(lockPath, O_RDWR | O_CREAT, 0o644)
        flock(fd, LOCK_EX)

        // Release after 150ms in detached task
        Task.detached {
            try? await Task.sleep(nanoseconds: 150_000_000)
            flock(fd, LOCK_UN)
            close(fd)
        }

        let freed = await manager.waitForLockRelease(
            prefix: tempDir.path,
            targetPackage: nil,
            timeout: 2.0,
            pollIntervalSeconds: 0.05
        )

        XCTAssertTrue(freed, "Wait should succeed once background task releases lock")
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWaitForLockReleaseTimesOutWhenLockRetained() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let locksDir = tempDir.appendingPathComponent("var/homebrew/locks")
        try FileManager.default.createDirectory(at: locksDir, withIntermediateDirectories: true)
        let lockPath = locksDir.appendingPathComponent("formula.lock").path

        let manager = BrewStoreLockManager(pidsChecker: { [] })

        let fd = open(lockPath, O_RDWR | O_CREAT, 0o644)
        flock(fd, LOCK_EX)

        let freed = await manager.waitForLockRelease(
            prefix: tempDir.path,
            targetPackage: nil,
            timeout: 0.2,
            pollIntervalSeconds: 0.05
        )

        XCTAssertFalse(freed, "Wait should timeout if lock is retained")

        flock(fd, LOCK_UN)
        close(fd)
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAllLockFilesAndHasActiveOrStaleLocks() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let locksDir = tempDir.appendingPathComponent("var/homebrew/locks")
        try FileManager.default.createDirectory(at: locksDir, withIntermediateDirectories: true)

        let manager = BrewStoreLockManager(pidsChecker: { [] })
        XCTAssertFalse(manager.hasActiveOrStaleLocks(prefix: tempDir.path))
        XCTAssertTrue(manager.allLockFiles(prefix: tempDir.path).isEmpty)

        // Create lock files and non-lock files
        let f1 = locksDir.appendingPathComponent("git.formula.lock")
        let f2 = locksDir.appendingPathComponent("update")
        let nonLock = locksDir.appendingPathComponent("ignored.txt")
        try "lock".write(to: f1, atomically: true, encoding: .utf8)
        try "update".write(to: f2, atomically: true, encoding: .utf8)
        try "ignore".write(to: nonLock, atomically: true, encoding: .utf8)

        XCTAssertTrue(manager.hasActiveOrStaleLocks(prefix: tempDir.path))
        let files = manager.allLockFiles(prefix: tempDir.path)
        XCTAssertEqual(Set(files), Set(["git.formula.lock", "update"]))

        // Force unlock
        let res = manager.forceUnlock(prefix: tempDir.path, terminateHoldingProcesses: false)
        XCTAssertEqual(Set(res.removedFiles), Set(["git.formula.lock", "update"]))
        XCTAssertFalse(manager.hasActiveOrStaleLocks(prefix: tempDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonLock.path), "Non-lock files should not be removed")

        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testHomebrewManagerClearLocksFlow() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let locksDir = tempDir.appendingPathComponent("var/homebrew/locks")
        try FileManager.default.createDirectory(at: locksDir, withIntermediateDirectories: true)
        let f1 = locksDir.appendingPathComponent("brew.lock")
        try "lock".write(to: f1, atomically: true, encoding: .utf8)

        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, _, _, category, _, _, _ in
            BrewStoreCommandResult(
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
        manager.isHomebrewLocked = true
        manager.errorMessage = "Operation blocked: Homebrew lock held by another process."

        _ = manager.clearLocks(terminateProcesses: false)
        XCTAssertFalse(manager.isHomebrewLocked)
        XCTAssertNil(manager.errorMessage)
        XCTAssertEqual(manager.activeLockState, HomebrewLockState.free)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
