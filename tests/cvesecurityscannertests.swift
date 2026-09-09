@testable import BrewStore
import Foundation
import XCTest

final class CVESecurityScannerTests: XCTestCase {
    @MainActor
    func testScanSuccess() async {
        let sampleAudit = """
        openssl@1.1:
          * CVE-2023-5678: Buffer overflow vulnerability in SSL handshake
          * Deprecated upstream
        node@16:
          * Warning: Formula is disabled and no longer supported
        """

        let mockRunner: BrewStoreCVESecurityScanner.CommandRunner = { _, _, _, _ in
            BrewStoreCommandResult(
                standardOutput: sampleAudit,
                standardError: "",
                terminationStatus: 0,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: .readOnly,
                launchErrorDescription: nil
            )
        }

        let scanner = BrewStoreCVESecurityScanner(commandRunner: mockRunner)
        let manager = HomebrewManager()

        XCTAssertFalse(scanner.isScanning)
        XCTAssertNil(scanner.scanError)
        XCTAssertNil(scanner.report)

        // Run validation of output directly
        let validation = BrewStoreCVESecurityScanner.validateAuditOutput(sampleAudit)
        guard case .success = validation else {
            XCTFail("Validation should have succeeded for valid audit output")
            return
        }

        // Run scan with mock runner
        scanner.scanSecurity(manager: manager)

        var attempts = 0
        while scanner.isScanning, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(scanner.isScanning, "Spinner must resolve on success")
        XCTAssertNil(scanner.scanError, "There should be no error on successful scan")
        XCTAssertNotNil(scanner.report, "Report should be populated")
        XCTAssertNotNil(scanner.lastScanDate)

        if let report = scanner.report {
            XCTAssertFalse(report.issues.isEmpty)
            XCTAssertTrue(report.issues.contains { $0.cveIdentifier == "CVE-2023-5678" })
            XCTAssertGreaterThanOrEqual(report.securityScore, 0)
            XCTAssertLessThanOrEqual(report.securityScore, 100)
        }
    }

    @MainActor
    func testScanTimeoutLifecycle() async {
        let timeoutRunner: BrewStoreCVESecurityScanner.CommandRunner = { _, _, _, _ in
            BrewStoreCommandResult(
                standardOutput: "",
                standardError: "Operation timed out",
                terminationStatus: nil,
                wasTerminated: true,
                didTimeOut: true,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: .readOnly,
                launchErrorDescription: nil
            )
        }

        let scanner = BrewStoreCVESecurityScanner(commandRunner: timeoutRunner)
        let manager = HomebrewManager()

        scanner.scanSecurity(manager: manager, timeout: 5)

        var attempts = 0
        while scanner.isScanning, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(scanner.isScanning, "Spinner must resolve after timeout")
        XCTAssertEqual(scanner.scanError, .timeout(seconds: 5))
        XCTAssertEqual(scanner.scanState, .failed(.timeout(seconds: 5)))
        XCTAssertEqual(scanner.scanError?.errorDescription, "Security audit timed out after 5s.")
        XCTAssertNotNil(scanner.scanError?.recoverySuggestion)
        XCTAssertTrue(scanner.scanError?.isRetryable == true)
    }

    @MainActor
    func testScanCancellation() {
        let scanner = BrewStoreCVESecurityScanner()
        XCTAssertFalse(scanner.isScanning)

        // Trigger cancel directly
        scanner.cancelScan()
        XCTAssertFalse(scanner.isScanning, "Spinner must resolve immediately on cancellation")
        XCTAssertEqual(scanner.scanError, .cancelled)
        XCTAssertEqual(scanner.scanState, .failed(.cancelled))
        XCTAssertEqual(scanner.scanError?.errorDescription, "Security audit was cancelled.")
        XCTAssertNotNil(scanner.scanError?.recoverySuggestion)
    }

    @MainActor
    func testScanMalformedAuditOutput() async {
        // 1. Direct validation tests
        let corruptOutput = "openssl@1.1:\n\u{00}\u{00}\u{00}MALFORMED_STREAM"
        let validation = BrewStoreCVESecurityScanner.validateAuditOutput(corruptOutput)

        switch validation {
        case let .failure(error):
            XCTAssertEqual(error, .malformedOutput(details: "Binary null byte (0x00) corruption detected in stream."))
            XCTAssertNotNil(error.recoverySuggestion)
            XCTAssertTrue(error.isRetryable)
        case .success:
            XCTFail("Validation should have failed for null bytes")
        }

        // Control character corruption (excluding tab and newline)
        let controlCorrupt = "audit:\n\u{07}\u{08}BEEP"
        let controlValidation = BrewStoreCVESecurityScanner.validateAuditOutput(controlCorrupt)
        switch controlValidation {
        case let .failure(error):
            XCTAssertEqual(error, .malformedOutput(details: "Illegal non-printable control characters detected in stream."))
        case .success:
            XCTFail("Validation should have failed for control characters")
        }

        // 2. Lifecycle test through scanner
        let corruptRunner: BrewStoreCVESecurityScanner.CommandRunner = { _, _, _, _ in
            BrewStoreCommandResult(
                standardOutput: corruptOutput,
                standardError: "",
                terminationStatus: 0,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: .readOnly,
                launchErrorDescription: nil
            )
        }

        let scanner = BrewStoreCVESecurityScanner(commandRunner: corruptRunner)
        let manager = HomebrewManager()

        scanner.scanSecurity(manager: manager)

        var attempts = 0
        while scanner.isScanning, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(scanner.isScanning, "Spinner must resolve on malformed output")
        XCTAssertEqual(scanner.scanError, .malformedOutput(details: "Binary null byte (0x00) corruption detected in stream."))
        XCTAssertEqual(scanner.scanState, .failed(.malformedOutput(details: "Binary null byte (0x00) corruption detected in stream.")))
    }

    @MainActor
    func testRetryableLockAndNetworkErrors() async {
        let lockError = CVEScanError.retryable(reason: "Homebrew lock is held by another running operation.", isLockError: true)
        XCTAssertTrue(lockError.isRetryable)
        XCTAssertTrue(lockError.recoverySuggestion?.contains("lockfile") == true)

        let netError = CVEScanError.retryable(reason: "Network connection to Homebrew advisory source failed.", isLockError: false)
        XCTAssertTrue(netError.isRetryable)
        XCTAssertTrue(netError.recoverySuggestion?.contains("transient") == true)

        // Lifecycle test with lockfile error from brew stderr
        let lockRunner: BrewStoreCVESecurityScanner.CommandRunner = { _, _, _, _ in
            BrewStoreCommandResult(
                standardOutput: "",
                standardError: "Error: Another active Homebrew process is already using the lockfile.",
                terminationStatus: 1,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: .readOnly,
                launchErrorDescription: nil
            )
        }

        let scanner = BrewStoreCVESecurityScanner(commandRunner: lockRunner)
        let manager = HomebrewManager()

        scanner.scanSecurity(manager: manager)

        var attempts = 0
        while scanner.isScanning, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(scanner.isScanning, "Spinner must resolve on lock error")
        XCTAssertEqual(scanner.scanError, .retryable(reason: "Homebrew lock is held by another running operation.", isLockError: true))
        XCTAssertTrue(scanner.scanError?.isRetryable == true)
    }

    @MainActor
    func testScanCommandFailureLifecycle() async {
        let failRunner: BrewStoreCVESecurityScanner.CommandRunner = { _, _, _, _ in
            BrewStoreCommandResult(
                standardOutput: "",
                standardError: "fatal: not a git repository",
                terminationStatus: 128,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: .readOnly,
                launchErrorDescription: nil
            )
        }

        let scanner = BrewStoreCVESecurityScanner(commandRunner: failRunner)
        let manager = HomebrewManager()

        scanner.scanSecurity(manager: manager)

        var attempts = 0
        while scanner.isScanning, attempts < 50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        XCTAssertFalse(scanner.isScanning, "Spinner must resolve on command failure")
        XCTAssertEqual(scanner.scanError, .commandFailed(exitCode: 128, message: "fatal: not a git repository"))
        XCTAssertTrue(scanner.scanError?.recoverySuggestion?.contains("Doctor") == true)
    }
}
