@testable import BrewStore
import Foundation
import XCTest

final class ExecutionSecurityBoundaryTests: XCTestCase {
    func testApprovedBinariesAllowed() {
        XCTAssertTrue(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/opt/homebrew/bin/brew"))
        XCTAssertTrue(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/usr/local/bin/brew"))
        XCTAssertTrue(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/usr/bin/pgrep"))
        XCTAssertTrue(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/usr/bin/osascript"))
        XCTAssertTrue(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/usr/bin/security"))
    }

    func testDisallowedBinariesBlocked() {
        XCTAssertFalse(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/tmp/evil_binary"))
        XCTAssertFalse(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/Users/test/Downloads/malware"))
        XCTAssertFalse(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/var/tmp/exploit"))
    }

    func testSanitizeEnvironmentRemovesDangerousVariables() {
        let dirtyEnv: [String: String] = [
            "USER": "developer",
            "HOME": "/Users/developer",
            "DYLD_INSERT_LIBRARIES": "/Library/Malicious/inject.dylib",
            "DYLD_LIBRARY_PATH": "/opt/injected/lib",
            "LD_PRELOAD": "/tmp/hook.so"
        ]

        let clean = ExecutionSecurityBoundary.sanitizeEnvironment(dirtyEnv)
        XCTAssertNil(clean["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(clean["DYLD_LIBRARY_PATH"])
        XCTAssertNil(clean["LD_PRELOAD"])
        XCTAssertEqual(clean["USER"], "developer")
        XCTAssertEqual(clean["HOME"], "/Users/developer")
        XCTAssertNotNil(clean["PATH"])
    }
}
