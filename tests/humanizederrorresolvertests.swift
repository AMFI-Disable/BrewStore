@testable import BrewStore
import XCTest

final class HumanizedErrorResolverTests: XCTestCase {

    func testResolveCancellation() {
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: "Operation cancelled by user.", wasCancelled: true)
        XCTAssertEqual(info.category, .cancelled)
        XCTAssertEqual(info.title, "Operation Cancelled")
        XCTAssertTrue(info.isRetryable)
    }

    func testResolveTimeout() {
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: "Command timed out after 900 seconds.", didTimeout: true)
        XCTAssertEqual(info.category, .timeout)
        XCTAssertEqual(info.title, "Operation Timed Out")
    }

    func testResolveLocks() {
        let raw = "Error: Another active Homebrew process, already in progress was found (pid 12345)."
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .lock)
        XCTAssertEqual(info.title, "Homebrew is Busy")
        XCTAssertTrue(info.suggestion.contains("Clear Locks"))
    }

    func testResolvePermissions() {
        let raw = "Error: Permission denied @ dir_s_mkdir - /opt/homebrew/Cellar"
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .permissions)
        XCTAssertEqual(info.title, "Administrator Privileges Required")
        XCTAssertTrue(info.suggestion.contains("elevated"))
    }

    func testResolveNetworkErrors() {
        let raw = "curl: (6) Could not resolve host: formulae.brew.sh"
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .network)
        XCTAssertEqual(info.title, "Network Connection Interrupted")
        XCTAssertTrue(info.suggestion.contains("Wi-Fi"))
    }

    func testResolveChecksumMismatch() {
        let raw = "Error: Checksum mismatch for /Users/test/Library/Caches/Homebrew/downloads/pkg.tar.gz"
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .checksum)
        XCTAssertEqual(info.title, "Download Verification Failed")
        XCTAssertTrue(info.suggestion.contains("Clear cache"))
    }

    func testResolveDeveloperToolsMissing() {
        let raw = "xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory is a command line tools instance"
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .developerTools)
        XCTAssertEqual(info.title, "Apple Developer Tools Required")
        XCTAssertTrue(info.suggestion.contains("xcode-select --install"))
    }

    func testResolveAppBundleCollision() {
        let raw = "Error: It seems there is already an App at '/Applications/VSCode.app'. Use --force to overwrite."
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .appCollision)
        XCTAssertEqual(info.title, "Application Already Installed")
        XCTAssertTrue(info.suggestion.contains("Adopt"))
    }

    func testResolveDependencyConflict() {
        let raw = "Error: Refusing to uninstall openssl@3 because it is required by python@3.11, which is currently installed."
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .dependencyConflict)
        XCTAssertEqual(info.title, "Refusing to Uninstall Package")
    }

    func testResolvePackageNotFound() {
        let raw = "Error: No available formula with the name \"nonexistent_pkg_123\"."
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .notFound)
        XCTAssertEqual(info.title, "Package Not Found")
    }

    func testResolveKegOnly() {
        let raw = "curl is keg-only, which means it was not symlinked into /opt/homebrew"
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .kegOnly)
        XCTAssertEqual(info.title, "Package Kept Isolated")
    }

    func testResolveGatekeeperQuarantine() {
        let raw = "Error: Cask quarantined: Apple cannot check it for malicious software"
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: raw)
        XCTAssertEqual(info.category, .quarantine)
        XCTAssertEqual(info.title, "macOS Gatekeeper Block")
        XCTAssertTrue(info.suggestion.contains("Privacy & Security"))
    }

    func testResolveExitCodeFallback() {
        let info = BrewStoreHumanizedErrorResolver.resolve(rawError: "", exitCode: 1)
        XCTAssertEqual(info.category, .generic)
        XCTAssertEqual(info.title, "Operation Incomplete")
        XCTAssertTrue(info.summary.contains("exit code 1"))
    }

    func testHumanizedMessageConvenience() {
        let msg = BrewStoreHumanizedErrorResolver.humanizedMessage(from: "curl: (7) Failed to connect to host")
        XCTAssertTrue(msg.contains("Network Connection Interrupted"))
    }

    func testHumanizedErrorBannerInitialization() {
        let banner = HumanizedErrorBanner(
            rawError: "curl: (6) Could not resolve host",
            titleOverride: "Custom Network Title",
            onDismiss: {},
            customActionTitle: "Retry Now",
            customAction: {}
        )
        XCTAssertNotNil(banner)
        XCTAssertEqual(banner.titleOverride, "Custom Network Title")
        XCTAssertEqual(banner.customActionTitle, "Retry Now")
    }
}
