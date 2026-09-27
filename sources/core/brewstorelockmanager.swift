import Darwin
import Foundation

enum HomebrewLockState: Equatable, Sendable {
    case free
    case locked(lockFileName: String, holdingPID: Int32?, message: String)

    var isLocked: Bool {
        if case .locked = self {
            return true
        }
        return false
    }

    var lockFileName: String? {
        if case let .locked(name, _, _) = self {
            return name
        }
        return nil
    }

    var holdingPID: Int32? {
        if case let .locked(_, pid, _) = self {
            return pid
        }
        return nil
    }
}

final class BrewStoreLockManager: @unchecked Sendable {
    static let shared = BrewStoreLockManager()

    typealias ActivePIDsChecker = @Sendable () -> [Int32]

    private let pidsChecker: ActivePIDsChecker

    init(pidsChecker: ActivePIDsChecker? = nil) {
        self.pidsChecker = pidsChecker ?? {
            var pids = Set<Int32>()
            let patterns = ["brew.rb", "bin/brew", "brew"]
            for pattern in patterns {
                let args = pattern == "brew" ? ["-x", pattern] : ["-f", pattern]
                let result = BrewStoreCommandExecutor.shared.run(
                    executablePath: "/usr/bin/pgrep",
                    arguments: args,
                    timeout: 3,
                    category: .readOnly
                )
                for line in result.standardOutput.split(whereSeparator: \.isNewline) {
                    if let pid = Int32(line.trimmingCharacters(in: .whitespaces)) {
                        pids.insert(pid)
                    }
                }
            }
            return Array(pids)
        }
    }

    /// Checks whether a specific lock file is currently locked by a running process using non-blocking flock.
    func isFileLocked(atPath path: String) -> Bool {
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        let result = flock(fd, LOCK_EX | LOCK_NB)
        if result == 0 {
            // Lock was available; release immediately
            flock(fd, LOCK_UN)
            return false
        } else {
            // Lock is held by another process (EWOULDBLOCK / EAGAIN)
            return errno == EWOULDBLOCK || errno == EAGAIN
        }
    }

    /// Inspects the Homebrew locks directory for any actively held locks.
    func checkLockState(prefix: String, targetPackage: String? = nil) -> HomebrewLockState {
        if BrewStoreFixtureMode.isEnabled, !prefix.contains("brewstore_fixture") {
            return .free
        }

        let locksDir = (prefix as NSString).appendingPathComponent("var/homebrew/locks")
        let fileManager = FileManager.default

        guard let lockFiles = try? fileManager.contentsOfDirectory(atPath: locksDir) else {
            return .free
        }

        let trimmedTarget = targetPackage?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let candidateFiles: [String]
        if let target = trimmedTarget, !target.isEmpty {
            let relevantSuffixes = [
                "\(target).formula.lock",
                "\(target).cask.lock",
                "\(target).lock"
            ]
            candidateFiles = lockFiles.filter { file in
                file == "update" ||
                    relevantSuffixes.contains(file.lowercased()) ||
                    file.lowercased().contains(target)
            }
        } else {
            candidateFiles = lockFiles
        }
        for file in candidateFiles {
            guard file.hasSuffix(".lock") || file == "update" else { continue }
            let fullPath = (locksDir as NSString).appendingPathComponent(file)

            if isFileLocked(atPath: fullPath) {
                let activePIDs = pidsChecker()
                let pid = activePIDs.first
                let msg: String = if let pid {
                    "Another Homebrew process (PID \(pid)) is currently using \(file)."
                } else {
                    "Another Homebrew process is currently using \(file)."
                }
                return .locked(lockFileName: file, holdingPID: pid, message: msg)
            }
        }

        return .free
    }

    /// Waits cooperatively for any active lock to be released, with a maximum timeout and cancellation check.
    func waitForLockRelease(
        prefix: String,
        targetPackage: String? = nil,
        timeout: TimeInterval = 10,
        pollIntervalSeconds: TimeInterval = 0.5,
        cancellationCheck: (@Sendable () -> Bool)? = nil
    ) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if cancellationCheck?() == true || Task.isCancelled {
                return false
            }

            let state = checkLockState(prefix: prefix, targetPackage: targetPackage)
            if state == .free {
                return true
            }

            try? await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
        }

        // Final check after timeout
        return checkLockState(prefix: prefix, targetPackage: targetPackage) == .free
    }

    /// Returns all lock file names currently present in the locks directory.
    func allLockFiles(prefix: String) -> [String] {
        if BrewStoreFixtureMode.isEnabled, !prefix.contains("brewstore_fixture") {
            return []
        }
        let locksDir = (prefix as NSString).appendingPathComponent("var/homebrew/locks")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: locksDir) else {
            return []
        }
        return files.filter { $0.hasSuffix(".lock") || $0 == "update" }
    }

    /// Checks if any lock files exist (held by flock or stale on disk).
    func hasActiveOrStaleLocks(prefix: String) -> Bool {
        !allLockFiles(prefix: prefix).isEmpty
    }

    /// Safely clears active or stale lock files and optionally terminates hanging brew processes.
    @discardableResult
    func forceUnlock(prefix: String, terminateHoldingProcesses: Bool = true) -> (removedFiles: [String], terminatedPIDs: [Int32]) {
        let locksDir = (prefix as NSString).appendingPathComponent("var/homebrew/locks")
        let fm = FileManager.default
        var removed: [String] = []
        var terminated: [Int32] = []

        if terminateHoldingProcesses {
            let activePIDs = pidsChecker()
            let myPID = getpid()
            for pid in activePIDs {
                guard pid > 1, pid != myPID else { continue }
                // Terminate hanging brew process
                kill(pid, SIGTERM)
                terminated.append(pid)
            }
        }

        let lockFiles = allLockFiles(prefix: prefix)
        for file in lockFiles {
            let fullPath = (locksDir as NSString).appendingPathComponent(file)
            if (try? fm.removeItem(atPath: fullPath)) != nil {
                removed.append(file)
            }
        }

        return (removed, terminated)
    }
}
