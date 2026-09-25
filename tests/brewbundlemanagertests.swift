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

final class BrewBundleManagerTests: XCTestCase {
    @MainActor
    func testTrackedBrewfilePersistence() {
        let manager = BrewStoreBundleManager.shared
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Brewfile_test_\(UUID().uuidString)")
        try? "brew \"gcc\"\n".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        manager.setTrackedBrewfile(url: tempURL)
        XCTAssertEqual(manager.trackedBrewfileURL?.path, tempURL.path)
    }

    @MainActor
    func testCheckDriftSatisfied() async {
        let manager = BrewStoreBundleManager.shared
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Brewfile_sat_\(UUID().uuidString)")
        let content = """
        tap "homebrew/core"
        brew "wget"
        cask "ghostty"
        """
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let pkg1 = BrewStorePackage(
            id: "wget",
            name: "wget",
            description: "Internet file retriever",
            homepage: "https://www.gnu.org/software/wget/",
            version: "1.24",
            kind: .formula,
            isInstalled: true
        )
        let pkg2 = BrewStorePackage(
            id: "ghostty",
            name: "ghostty",
            description: "Terminal emulator",
            homepage: "https://ghostty.org",
            version: "1.0",
            kind: .cask,
            isInstalled: true
        )
        let tap = BrewStoreTap(id: "homebrew/core", name: "homebrew/core")

        let report = await manager.checkDrift(for: tempURL, packages: [pkg1, pkg2], taps: [tap])

        XCTAssertEqual(report.status, .satisfied)
        XCTAssertTrue(report.missingFormulae.isEmpty)
        XCTAssertTrue(report.missingCasks.isEmpty)
        XCTAssertTrue(report.missingTaps.isEmpty)
        XCTAssertTrue(report.isSatisfied)
    }

    @MainActor
    func testCheckDriftDetectsMissingAndUnmanaged() async {
        let manager = BrewStoreBundleManager.shared
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Brewfile_drift_\(UUID().uuidString)")
        let content = """
        tap "custom/tap"
        brew "missing_tool"
        cask "missing_app"
        """
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let unmanagedPkg = BrewStorePackage(
            id: "extra_tool",
            name: "extra_tool",
            description: "Unmanaged package",
            homepage: "https://example.com",
            version: "2.0",
            kind: .formula,
            isInstalled: true
        )

        let report = await manager.checkDrift(for: tempURL, packages: [unmanagedPkg], taps: [])

        XCTAssertEqual(report.status, .drifted)
        XCTAssertEqual(report.missingFormulae, ["missing_tool"])
        XCTAssertEqual(report.missingCasks, ["missing_app"])
        XCTAssertEqual(report.missingTaps, ["custom/tap"])
        XCTAssertTrue(report.unmanagedFormulae.contains("extra_tool"))
        XCTAssertFalse(report.isSatisfied)
        XCTAssertEqual(report.totalMissingCount, 3)
    }

    @MainActor
    func testScanDirectoryFindsBrewfiles() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("scan_test_\(UUID().uuidString)")
        let subDir = tempDir.appendingPathComponent("subproject", isDirectory: true)
        try? FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rootBrewfile = tempDir.appendingPathComponent("Brewfile")
        let dotBrewfile = tempDir.appendingPathComponent(".Brewfile")
        let subBrewfile = subDir.appendingPathComponent("Brewfile")

        try? "brew \"curl\"\n".write(to: rootBrewfile, atomically: true, encoding: .utf8)
        try? "brew \"git\"\n".write(to: dotBrewfile, atomically: true, encoding: .utf8)
        try? "brew \"node\"\n".write(to: subBrewfile, atomically: true, encoding: .utf8)

        let manager = BrewStoreBundleManager.shared
        let found = await manager.scanDirectory(at: tempDir)
        let foundPaths = Set(found.map { $0.resolvingSymlinksInPath().path })

        XCTAssertTrue(foundPaths.contains(rootBrewfile.resolvingSymlinksInPath().path))
        XCTAssertTrue(foundPaths.contains(dotBrewfile.resolvingSymlinksInPath().path))
        XCTAssertTrue(foundPaths.contains(subBrewfile.resolvingSymlinksInPath().path))
    }

    func testParseCleanupItemsOutput() {
        let rawOutput = """
        ==> Checking Homebrew dependencies...
        Would uninstall casks:
        firefox
        google-chrome
        Would uninstall formulae:
        ansible
        terraform
        """

        let items = BrewStoreBundleManager.parseCleanupItems(from: rawOutput)
        XCTAssertEqual(items, ["firefox", "google-chrome", "ansible", "terraform"])
    }

    @MainActor
    func testDumpSystemBrewfileExecution() async {
        let recorder = SafeArgsRecorder()
        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            recorder.record(arguments)
            return BrewStoreCommandResult(
                standardOutput: "Dumped",
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
        let manager = BrewStoreBundleManager(commandExecutor: customExecutor)
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent("dump_test.Brewfile")

        let res = await manager.dumpSystemBrewfile(to: targetURL, includeComments: true)
        XCTAssertTrue(res.success)
        XCTAssertTrue(
            recorder.invocations.contains {
                $0.contains("bundle") && $0.contains("dump") && $0.contains("--force")
            },
            "Expected 'bundle dump --force' invocation in \(recorder.invocations)"
        )
    }

    @MainActor
    func testInstallBundleExecution() async {
        let recorder = SafeArgsRecorder()
        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            recorder.record(arguments)
            return BrewStoreCommandResult(
                standardOutput: "Installed",
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
        let manager = BrewStoreBundleManager(commandExecutor: customExecutor)
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent("install_test.Brewfile")

        let res = await manager.installBundle(from: targetURL, noLock: true)
        XCTAssertTrue(res.success)
        XCTAssertTrue(
            recorder.invocations.contains {
                $0.contains("bundle") && $0.contains("install") && $0.contains("--no-lock")
            },
            "Expected 'bundle install --no-lock' invocation in \(recorder.invocations)"
        )
    }

    @MainActor
    func testExecuteCleanupExecution() async {
        let recorder = SafeArgsRecorder()
        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            recorder.record(arguments)
            return BrewStoreCommandResult(
                standardOutput: "Cleaned up",
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
        let manager = BrewStoreBundleManager(commandExecutor: customExecutor)
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup_test.Brewfile")

        let res = await manager.executeCleanup(for: targetURL, zap: true)
        XCTAssertTrue(res.success)
        XCTAssertTrue(
            recorder.invocations.contains {
                $0.contains("bundle") && $0.contains("cleanup") && $0.contains("--force") && $0.contains("--zap")
            },
            "Expected 'bundle cleanup --force --zap' invocation in \(recorder.invocations)"
        )
    }
}
