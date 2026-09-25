@testable import BrewStore
import Foundation
import XCTest

private final class SafeArgsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _invocations: [[String]] = []

    var invocations: [[String]] {
        lock.withLock { _invocations }
    }

    func record(_ args: [String]) {
        lock.withLock { _invocations.append(args) }
    }
}

final class TapHealthManagerTests: XCTestCase {
    @MainActor
    func testOfficialTapHealthAudit() {
        let manager = BrewStoreTapHealthManager.shared
        let officialTap = BrewStoreTap(
            id: "homebrew/core",
            name: "homebrew/core"
        )

        manager.auditTap(tap: officialTap, prefix: nil)
        let report = manager.report(for: "homebrew/core")

        XCTAssertNotNil(report)
        XCTAssertEqual(report?.status, .healthy)
        XCTAssertEqual(report?.hostProvider, "GitHub")
        XCTAssertTrue(report?.notes?.contains("Official") == true)
        XCTAssertTrue(report?.isOfficial == true)
    }

    @MainActor
    func testThirdPartyTapHealthAudit() {
        let manager = BrewStoreTapHealthManager.shared
        let customTap = BrewStoreTap(
            id: "custom/tools",
            name: "custom/tools"
        )

        manager.auditTap(tap: customTap, prefix: nil)
        let report = manager.report(for: "custom/tools")

        XCTAssertNotNil(report)
        XCTAssertNotNil(report?.remoteURL)
    }

    func testDetectTransportProtocol() {
        XCTAssertEqual(
            BrewStoreTapHealthManager.detectProtocol(from: "https://github.com/foo/bar.git"),
            .https
        )
        XCTAssertEqual(
            BrewStoreTapHealthManager.detectProtocol(from: "http://gitlab.com/foo/bar"),
            .https
        )
        XCTAssertEqual(
            BrewStoreTapHealthManager.detectProtocol(from: "git@github.com:foo/bar.git"),
            .ssh
        )
        XCTAssertEqual(
            BrewStoreTapHealthManager.detectProtocol(from: "ssh://git@codeberg.org/foo/bar.git"),
            .ssh
        )
        XCTAssertEqual(
            BrewStoreTapHealthManager.detectProtocol(from: "file:///local/path"),
            .fileOrCustom
        )
    }

    func testConvertRemoteURL() {
        // HTTPS -> SSH
        let toSSH = BrewStoreTapHealthManager.convertRemoteURL(
            "https://github.com/user/custom-tap",
            to: .ssh
        )
        XCTAssertEqual(toSSH, "git@github.com:user/custom-tap.git")

        // SSH -> HTTPS
        let toHTTPS = BrewStoreTapHealthManager.convertRemoteURL(
            "git@github.com:user/custom-tap.git",
            to: .https
        )
        XCTAssertEqual(toHTTPS, "https://github.com/user/custom-tap.git")

        // ssh:// format -> HTTPS
        let sshPrefixToHTTPS = BrewStoreTapHealthManager.convertRemoteURL(
            "ssh://git@gitlab.com/group/tap.git",
            to: .https
        )
        XCTAssertEqual(sshPrefixToHTTPS, "https://gitlab.com/group/tap.git")
    }

    func testParseAheadBehindCommitLag() {
        let upToDate = BrewStoreTapHealthManager.parseAheadBehind(from: "0\t0\n")
        XCTAssertEqual(upToDate.ahead, 0)
        XCTAssertEqual(upToDate.behind, 0)

        let behindThree = BrewStoreTapHealthManager.parseAheadBehind(from: "1\t3\n")
        XCTAssertEqual(behindThree.ahead, 1)
        XCTAssertEqual(behindThree.behind, 3)

        let invalid = BrewStoreTapHealthManager.parseAheadBehind(from: "fatal: not a git repo")
        XCTAssertEqual(invalid.ahead, 0)
        XCTAssertEqual(invalid.behind, 0)
    }

    func testLatencyProbeURLResolution() {
        let ghHTTPS = BrewStoreTapHealthManager.resolveLatencyProbeURL(from: "https://github.com/user/tap.git")
        XCTAssertEqual(ghHTTPS, "https://github.com")

        let glSSH = BrewStoreTapHealthManager.resolveLatencyProbeURL(from: "git@gitlab.com:user/tap.git")
        XCTAssertEqual(glSSH, "https://gitlab.com")
    }

    @MainActor
    func testSyncTapCommandExecution() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tap_test_\(UUID().uuidString)")
        let tapDir = tempDir
            .appendingPathComponent("Library/Taps/testuser/homebrew-testrepo", isDirectory: true)
        try? FileManager.default.createDirectory(at: tapDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let recorder = SafeArgsRecorder()
        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            recorder.record(arguments)
            return BrewStoreCommandResult(
                standardOutput: "Already up to date.",
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

        let customExecutor = BrewStoreCommandExecutor(customHandler: customHandler)
        let healthManager = BrewStoreTapHealthManager(commandExecutor: customExecutor)

        let res = await healthManager.syncTap(tapName: "testuser/testrepo", prefix: tempDir.path)
        XCTAssertTrue(res.success, "Expected success but got: \(res.message)")
        XCTAssertTrue(
            recorder.invocations.contains { $0.contains("pull") && $0.contains("--prune") },
            "Expected 'pull --prune' invocation in \(recorder.invocations)"
        )
    }

    @MainActor
    func testRepairTapCommandExecution() async {
        let recorder = SafeArgsRecorder()
        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            recorder.record(arguments)
            return BrewStoreCommandResult(
                standardOutput: "Repaired testuser/testrepo",
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

        let customExecutor = BrewStoreCommandExecutor(customHandler: customHandler)
        let healthManager = BrewStoreTapHealthManager(commandExecutor: customExecutor)

        let res = await healthManager.repairTap(tapName: "testuser/testrepo", prefix: "/tmp/mock_prefix")
        XCTAssertTrue(res.success)
        XCTAssertTrue(
            recorder.invocations.contains { $0 == ["tap", "--repair", "testuser/testrepo"] },
            "Expected 'tap --repair' invocation in \(recorder.invocations)"
        )
    }

    @MainActor
    func testSwitchProtocolCommandExecution() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tap_proto_\(UUID().uuidString)")
        let tapDir = tempDir
            .appendingPathComponent("Library/Taps/testuser/homebrew-testrepo", isDirectory: true)
        try? FileManager.default.createDirectory(at: tapDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let recorder = SafeArgsRecorder()
        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            recorder.record(arguments)
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

        let customExecutor = BrewStoreCommandExecutor(customHandler: customHandler)
        let healthManager = BrewStoreTapHealthManager(commandExecutor: customExecutor)

        // Seed initial report with HTTPS remote
        let initialReport = TapHealthReport(
            tapName: "testuser/testrepo",
            remoteURL: "https://github.com/testuser/homebrew-testrepo.git",
            hostProvider: "GitHub",
            status: .healthy,
            transportProtocol: .https
        )
        healthManager.reports["testuser/testrepo"] = initialReport

        let res = await healthManager.switchProtocol(
            tapName: "testuser/testrepo",
            to: .ssh,
            prefix: tempDir.path
        )
        XCTAssertTrue(res.success, "Expected success but got: \(res.message)")
        XCTAssertTrue(
            recorder.invocations.contains {
                $0.contains("remote") &&
                    $0.contains("set-url") &&
                    $0.contains("origin") &&
                    $0.contains("git@github.com:testuser/homebrew-testrepo.git")
            },
            "Expected 'remote set-url origin' invocation in \(recorder.invocations)"
        )
    }
}
