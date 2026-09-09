import Foundation

/// Provides an isolated, disposable fixture-driven environment for exercising
/// BrewStore's destructive workflows (uninstall, autoremove, snapshot restore/delete,
/// service/tap mutations, and cancellation/partial-failure handling) without modifying
/// the host's actual Homebrew installation.
final class BrewStoreFixtureMode: @unchecked Sendable {
    /// Thread-safe lock for mutable override state
    private static let lock = NSLock()
    private static var _isOverrideActive = false
    private static var _temporarySnapshotURL: URL?

    /// Indicates whether fixture smoke-test mode is currently active.
    /// Triggered by:
    /// 1. Environment variable `BREWSTORE_FIXTURE_MODE=1`
    /// 2. Launch argument `--fixture-smoke-test`
    /// 3. Programmatic override (e.g. during unit tests)
    static var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }

        if _isOverrideActive {
            return true
        }
        let env = ProcessInfo.processInfo.environment["BREWSTORE_FIXTURE_MODE"]
        if env == "1" || env?.lowercased() == "true" {
            return true
        }
        return ProcessInfo.processInfo.arguments.contains("--fixture-smoke-test")
    }

    /// Explicitly enable or disable fixture mode for automated test suites.
    static func setOverrideActive(_ active: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _isOverrideActive = active
    }

    /// Disposable snapshots directory used when fixture mode is active.
    static var customSnapshotsDirectory: URL? {
        guard isEnabled else { return nil }
        lock.lock()
        defer { lock.unlock() }

        if let existing = _temporarySnapshotURL, FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("brewstore_fixture_\(UUID().uuidString)")
            .appendingPathComponent("Snapshots", isDirectory: true)

        try? FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        seedInitialSnapshots(into: tempBase)
        _temporarySnapshotURL = tempBase
        return tempBase
    }

    /// Pre-populates the disposable fixture directory with valid, testable Brewfile snapshots.
    private static func seedInitialSnapshots(into directory: URL) {
        let sampleSnapshot1 = """
        # BrewStore Fixture Snapshot Alpha
        tap "homebrew/core"
        tap "homebrew/cask"
        brew "ripgrep"
        brew "jq"
        brew "htop"
        cask "iterm2"
        cask "visual-studio-code"
        """

        let sampleSnapshot2 = """
        # BrewStore Fixture Snapshot Beta
        tap "homebrew/core"
        brew "ripgrep"
        brew "node"
        cask "raycast"
        """

        let file1 = directory.appendingPathComponent("Brewfile-2026-09-01-100000")
        let file2 = directory.appendingPathComponent("Brewfile-2026-09-02-120000")

        try? sampleSnapshot1.write(to: file1, atomically: true, encoding: .utf8)
        try? sampleSnapshot2.write(to: file2, atomically: true, encoding: .utf8)
    }

    /// Cleans up any disposable snapshot fixtures created during testing.
    static func cleanupFixtureEnvironment() {
        lock.lock()
        defer { lock.unlock() }
        if let dir = _temporarySnapshotURL {
            try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
            _temporarySnapshotURL = nil
        }
    }

    /// Intercepts destructive Homebrew commands and simulates deterministic outcomes
    /// (success, cancellation, and simulated errors) without running real system commands.
    static let fixtureCommandHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, cancellationCheck, onOutput in
        // Only intercept brew commands when in fixture mode
        guard isEnabled else { return nil }

        // Check cancellation first
        if cancellationCheck?() == true {
            return BrewStoreCommandResult(
                standardOutput: "",
                standardError: "Operation cancelled by user.",
                terminationStatus: 130,
                wasTerminated: true,
                didTimeOut: false,
                wasCancelled: true,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: category,
                launchErrorDescription: nil
            )
        }

        let cmd = arguments.first ?? ""

        // 1. Uninstall Commands (Single / Batch)
        if cmd == "uninstall" {
            let targetPackages = arguments.dropFirst().filter { !$0.hasPrefix("-") }
            let shouldFail = targetPackages.contains { $0.contains("fail") || $0.contains("broken") }

            if shouldFail {
                let errText = "Error: Refusing to uninstall '\(targetPackages.joined(separator: ", "))': simulated lock or dependency failure."
                onOutput?(errText + "\n")
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: errText,
                    terminationStatus: 1,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }

            var out = ""
            for pkg in targetPackages {
                out += "==> Uninstalling \(pkg)...\n==> Purging files for \(pkg)...\n"
            }
            out += "==> Successfully uninstalled \(targetPackages.joined(separator: ", "))\n"
            onOutput?(out)

            return BrewStoreCommandResult(
                standardOutput: out,
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

        // 2. Autoremove Command
        if cmd == "autoremove" {
            let out = "==> Autoremoved 3 unneeded dependencies:\n  libevent, libidn2, utf8proc\n"
            onOutput?(out)
            return BrewStoreCommandResult(
                standardOutput: out,
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

        // 3. Services Commands (start, stop, restart, run)
        if cmd == "services" {
            let subaction = arguments.count > 1 ? arguments[1] : "list"
            let targetService = arguments.count > 2 ? arguments[2] : "all"
            let shouldFail = targetService.contains("fail") || targetService.contains("error")

            if shouldFail {
                let errText = "Error: Service '\(targetService)' failed to \(subaction): launchd plist rejected (simulated)."
                onOutput?(errText + "\n")
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: errText,
                    terminationStatus: 1,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }

            let out = "==> Successfully \(subaction)ed `\(targetService)` (label: homebrew.mxcl.\(targetService))\n"
            onOutput?(out)
            return BrewStoreCommandResult(
                standardOutput: out,
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

        // 4. Tap Commands (tap, untap)
        if cmd == "tap" || cmd == "untap" {
            let targetTap = arguments.dropFirst().first { !$0.hasPrefix("-") } ?? "custom/tap"
            let shouldFail = targetTap.contains("fail") || targetTap.contains("invalid")

            if shouldFail {
                let errText = "Error: Failed to \(cmd) '\(targetTap)': repository not found or network error (simulated)."
                onOutput?(errText + "\n")
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: errText,
                    terminationStatus: 1,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            }

            let out = cmd == "tap" ? "==> Tapped 1 tap (1 formula)\n" : "==> Untapped \(targetTap)\n"
            onOutput?(out)
            return BrewStoreCommandResult(
                standardOutput: out,
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

        // 5. Package Install / Reinstall (e.g. during Snapshot Rollback restore phase)
        if cmd == "install" || cmd == "reinstall" {
            let targetPackages = arguments.dropFirst().filter { !$0.hasPrefix("-") }
            let out = "==> Downloading and installing \(targetPackages.joined(separator: ", "))...\n==> Successfully installed \(targetPackages.joined(separator: ", "))\n"
            onOutput?(out)
            return BrewStoreCommandResult(
                standardOutput: out,
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

        // For all non-destructive/read-only commands (e.g. list, outdated, info), return nil so standard read operations proceed normally
        return nil
    }
}
