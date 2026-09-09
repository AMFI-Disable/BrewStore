@testable import BrewStore
import Foundation
import XCTest

final class HomebrewManagerRefreshTests: XCTestCase {
    private final class RefreshTestState: @unchecked Sendable {
        private let lock = NSLock()
        private var commandCount = 0
        private var shouldFailFormulaCatalog = true

        func incrementCommandCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            commandCount += 1
            return commandCount
        }

        func observedCommandCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return commandCount
        }

        func takeFormulaFailureFlag() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let shouldFail = shouldFailFormulaCatalog
            shouldFailFormulaCatalog = false
            return shouldFail
        }
    }

    private func result(
        output: String = "",
        error: String = "",
        status: Int32? = 0,
        category: BrewStoreCommandCategory
    ) -> BrewStoreCommandResult {
        BrewStoreCommandResult(
            standardOutput: output,
            standardError: error,
            terminationStatus: status,
            wasTerminated: false,
            didTimeOut: false,
            wasCancelled: false,
            standardOutputWasTruncated: false,
            standardErrorWasTruncated: false,
            category: category,
            launchErrorDescription: nil
        )
    }

    private func makeCaskJSON(id: String, name: String) -> String {
        """
        [
          {
            "token": "\(id)",
            "name": ["\(name)"],
            "desc": "Test Description",
            "homepage": "https://example.com",
            "version": "1.0.0",
            "installed": null,
            "outdated": false
          }
        ]
        """
    }

    private func makeFormulaJSON(id: String, name _: String) -> String {
        """
        [
          {
            "name": "\(id)",
            "full_name": "\(id)",
            "desc": "Test Formula Description",
            "homepage": "https://example.com",
            "versions": {
              "stable": "1.0.0"
            },
            "installed": [],
            "outdated": false,
            "pinned": false
          }
        ]
        """
    }

    @MainActor
    func testRefreshFormulaFailureDoesNotReportSuccess() async {
        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, args, _, category, _, _, _ in
            if args.contains("--cask"), args.contains("info") {
                return BrewStoreCommandResult(
                    standardOutput: self.makeCaskJSON(id: "test-cask", name: "Test Cask"),
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
            } else if args.contains("--formula"), args.contains("info") {
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: "fatal: formula catalog index unavailable",
                    terminationStatus: 1,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: false,
                    standardErrorWasTruncated: false,
                    category: category,
                    launchErrorDescription: nil
                )
            } else if args.contains("list") {
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
            } else if args.contains("outdated") {
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

        manager.refresh()

        var attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(manager.isLoading)
        XCTAssertNotNil(manager.errorMessage, "Error message must be shown when formula catalog fails")
        XCTAssertTrue(manager.errorMessage?.contains("Failed to load formula catalog") == true)
        XCTAssertTrue(manager.errorMessage?.contains("Tap Refresh to retry.") == true)
        XCTAssertEqual(manager.statusMessage, "Refresh failed (tap to retry).")
        XCTAssertFalse(manager.statusMessage.contains("Updated"), "Partial failure must never be reported as updated catalog")

        if case .formulaCatalogFailed = manager.catalogRefreshError {
            // Expected
        } else {
            XCTFail("Expected .formulaCatalogFailed error, got \(String(describing: manager.catalogRefreshError))")
        }
    }

    @MainActor
    func testRefreshTruncatedOutputIsRejected() async {
        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, args, _, category, _, _, _ in
            if args.contains("info"), args.contains("--cask") {
                return BrewStoreCommandResult(
                    standardOutput: "[{\"token\":\"truncated...",
                    standardError: "",
                    terminationStatus: 0,
                    wasTerminated: false,
                    didTimeOut: false,
                    wasCancelled: false,
                    standardOutputWasTruncated: true, // TRUNCATED
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

        manager.refresh()

        var attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(manager.isLoading)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertTrue(manager.errorMessage?.contains("truncated") == true)
        XCTAssertTrue(manager.errorMessage?.contains("Tap Refresh to retry.") == true)
        XCTAssertEqual(manager.statusMessage, "Refresh failed (tap to retry).")

        if case let .truncatedOutput(cmd) = manager.catalogRefreshError {
            XCTAssertEqual(cmd, "cask catalog")
        } else {
            XCTFail("Expected .truncatedOutput error, got \(String(describing: manager.catalogRefreshError))")
        }
    }

    @MainActor
    func testRefreshListCommandFailureIsRejected() async {
        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, args, _, category, _, _, _ in
            if args.contains("list"), args.contains("--formula") {
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: "brew list --formula failed: command terminated",
                    terminationStatus: 127,
                    wasTerminated: true,
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

        manager.refresh()

        var attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(manager.isLoading)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertTrue(manager.errorMessage?.contains("Failed to query installed formulae") == true)
        XCTAssertTrue(manager.errorMessage?.contains("Tap Refresh to retry.") == true)
        XCTAssertEqual(manager.statusMessage, "Refresh failed (tap to retry).")
    }

    @MainActor
    func testRefreshOutdatedCommandFailureIsRejected() async {
        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, args, _, category, _, _, _ in
            if args.contains("outdated") {
                return BrewStoreCommandResult(
                    standardOutput: "",
                    standardError: "outdated command timed out",
                    terminationStatus: nil,
                    wasTerminated: true,
                    didTimeOut: true,
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

        manager.refresh()

        var attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(manager.isLoading)
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertTrue(manager.errorMessage?.contains("Failed to check outdated packages") == true)
        XCTAssertTrue(manager.errorMessage?.contains("Tap Refresh to retry.") == true)
        XCTAssertEqual(manager.statusMessage, "Refresh failed (tap to retry).")
    }

    @MainActor
    func testRefreshReconcilesAuthoritativeInstalledCounts() async {
        let caskCatalogJSON = """
        [
          {
            "token": "iterm2",
            "name": ["iTerm2"],
            "desc": "Terminal emulator",
            "homepage": "https://iterm2.com",
            "version": "3.5.0",
            "installed": null,
            "outdated": false
          },
          {
            "token": "firefox",
            "name": ["Firefox"],
            "desc": "Web browser",
            "homepage": "https://mozilla.org",
            "version": "125.0",
            "installed": null,
            "outdated": false
          }
        ]
        """

        let formulaCatalogJSON = """
        [
          {
            "name": "git",
            "full_name": "git",
            "desc": "Distributed version control",
            "homepage": "https://git-scm.com",
            "versions": { "stable": "2.45.0" },
            "installed": [],
            "outdated": false,
            "pinned": false
          },
          {
            "name": "curl",
            "full_name": "curl",
            "desc": "Data transfer tool",
            "homepage": "https://curl.se",
            "versions": { "stable": "8.7.1" },
            "installed": [],
            "outdated": false,
            "pinned": false
          }
        ]
        """

        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, args, _, category, _, _, _ in
            if args.contains("--cask"), args.contains("--versions") {
                // Authoritative casks: 1 installed (iterm2 3.5.0)
                return BrewStoreCommandResult(
                    standardOutput: "iterm2 3.5.0\n",
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
            } else if args.contains("--formula"), args.contains("--versions") {
                // Authoritative formulae: 1 installed (git 2.45.0)
                return BrewStoreCommandResult(
                    standardOutput: "git 2.45.0\n",
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
            } else if args.contains("info"), args.contains("--cask") {
                return BrewStoreCommandResult(
                    standardOutput: caskCatalogJSON,
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
            } else if args.contains("info"), args.contains("--formula") {
                return BrewStoreCommandResult(
                    standardOutput: formulaCatalogJSON,
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
            } else if args.contains("outdated") {
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

        manager.refresh()

        var attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(manager.isLoading)
        XCTAssertNil(manager.errorMessage)
        XCTAssertNil(manager.catalogRefreshError)
        XCTAssertTrue(manager.statusMessage.contains("2 installed") || manager.statusMessage.contains("2 packages"))

        let installedCasks = manager.packages.filter { $0.kind == .cask && $0.isInstalled }
        let installedFormulae = manager.packages.filter { $0.kind == .formula && $0.isInstalled }

        XCTAssertEqual(installedCasks.count, 1, "Exactly 1 cask should be reconciled as installed")
        XCTAssertEqual(installedCasks.first?.id, "iterm2")
        XCTAssertEqual(installedCasks.first?.installedVersion, "3.5.0")

        XCTAssertEqual(installedFormulae.count, 1, "Exactly 1 formula should be reconciled as installed")
        XCTAssertEqual(installedFormulae.first?.id, "git")
        XCTAssertEqual(installedFormulae.first?.installedVersion, "2.45.0")

        // Uninstalled packages should not be marked as installed
        let firefox = manager.packages.first { $0.id == "firefox" }
        XCTAssertNotNil(firefox)
        XCTAssertFalse(firefox?.isInstalled == true)

        let curl = manager.packages.first { $0.id == "curl" }
        XCTAssertNotNil(curl)
        XCTAssertFalse(curl?.isInstalled == true)
    }

    @MainActor
    func testRefreshSynthesizesFallbackForOmittedInstalledPackage() async {
        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, args, _, category, _, _, _ in
            if args.contains("--cask"), args.contains("--versions") {
                // Authoritative list has a custom unlisted cask
                return BrewStoreCommandResult(
                    standardOutput: "custom-internal-app 4.1.0\n",
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
            } else if args.contains("info"), args.contains("--cask") {
                // Catalog API returns empty array (omitted custom-internal-app)
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
            } else if args.contains("info"), args.contains("--formula") {
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
            } else if args.contains("outdated") {
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

        manager.refresh()

        var attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(manager.isLoading)
        XCTAssertNil(manager.errorMessage)
        XCTAssertEqual(manager.packages.count, 1)

        let synthesized = manager.packages.first
        XCTAssertEqual(synthesized?.id, "custom-internal-app")
        XCTAssertEqual(synthesized?.kind, .cask)
        XCTAssertEqual(synthesized?.isInstalled, true)
        XCTAssertEqual(synthesized?.installedVersion, "4.1.0")
        XCTAssertEqual(synthesized?.version, "4.1.0")
    }

    @MainActor
    func testRefreshIgnoresRepeatedRequestsWhileLoading() async {
        let state = RefreshTestState()
        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, args, _, category, _, _, _ in
            _ = state.incrementCommandCount()
            Thread.sleep(forTimeInterval: 0.02)

            if args.contains("outdated") {
                return self.result(output: "{\"formulae\":[],\"casks\":[]}", category: category)
            }
            return self.result(category: category)
        }

        let manager = HomebrewManager(executor: BrewStoreCommandExecutor(customHandler: mockHandler))
        manager.refresh()
        manager.refresh()

        var attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        let observedCommandCount = state.observedCommandCount()
        XCTAssertFalse(manager.isLoading)
        XCTAssertEqual(observedCommandCount, 8, "A repeated refresh must not start a second command batch")
    }

    @MainActor
    func testRetryRefreshClearsFailureAfterTransientCatalogError() async {
        let state = RefreshTestState()
        let mockHandler: BrewStoreCommandExecutor.CustomHandler = { _, args, _, category, _, _, _ in
            if args.contains("info"), args.contains("--formula") {
                if state.takeFormulaFailureFlag() {
                    return self.result(
                        error: "temporary formula catalog outage",
                        status: 1,
                        category: category
                    )
                }
            }

            if args.contains("outdated") {
                return self.result(output: "{\"formulae\":[],\"casks\":[]}", category: category)
            }
            return self.result(category: category)
        }

        let manager = HomebrewManager(executor: BrewStoreCommandExecutor(customHandler: mockHandler))
        manager.refresh()

        var attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
        XCTAssertNotNil(manager.catalogRefreshError)
        XCTAssertFalse(manager.isLoading)

        manager.retryRefresh()
        attempts = 0
        while manager.isLoading, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(manager.isLoading)
        XCTAssertNil(manager.catalogRefreshError)
        XCTAssertNil(manager.errorMessage)
        XCTAssertTrue(manager.statusMessage.contains("up to date") || manager.statusMessage.contains("Synced") || manager.statusMessage.contains("packages"))
    }
}
