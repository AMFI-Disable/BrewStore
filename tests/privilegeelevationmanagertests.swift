@testable import BrewStore
import Foundation
import XCTest

final class PrivilegeElevationManagerTests: XCTestCase {
    func testRequiresElevationForCaveats() {
        let manager = BrewStorePrivilegeElevationManager()

        let normalPackage = BrewStorePackage(
            id: "wget",
            name: "wget",
            description: "Download utility",
            homepage: "https://gnu.org",
            version: "1.24.5",
            kind: .formula
        )
        XCTAssertEqual(manager.requiresElevation(package: normalPackage, action: .install), .notRequired)

        let privilegedCask = BrewStorePackage(
            id: "virtual-driver",
            name: "Virtual Driver",
            description: "Kernel driver",
            homepage: "https://example.com",
            version: "1.0.0",
            kind: .cask,
            caveats: "This app requires sudo permissions to install a system extension."
        )
        let status = manager.requiresElevation(package: privilegedCask, action: .install)
        if case let .required(reason) = status {
            XCTAssertTrue(reason.contains("system extensions") || reason.contains("root"))
        } else {
            XCTFail("Expected .required for cask with sudo caveats")
        }
    }

    func testIsPrivilegeErrorDetection() {
        let manager = BrewStorePrivilegeElevationManager()

        XCTAssertTrue(manager.isPrivilegeError(
            errorMessage: "sudo: a terminal is required to read the password",
            outputLog: ""
        ))

        XCTAssertTrue(manager.isPrivilegeError(
            errorMessage: "Error: Operation not permitted",
            outputLog: "installer: Error: Need sudo access to install this package"
        ))

        XCTAssertFalse(manager.isPrivilegeError(
            errorMessage: "Error: No available formula with the name 'unknown-tool'",
            outputLog: "404 Not Found"
        ))
    }

    func testEscapeShellArgument() {
        XCTAssertEqual(BrewStorePrivilegeElevationManager.escapeShellArgument("hello"), "'hello'")
        XCTAssertEqual(BrewStorePrivilegeElevationManager.escapeShellArgument("foo bar"), "'foo bar'")
        XCTAssertEqual(BrewStorePrivilegeElevationManager.escapeShellArgument("don't"), "'don'\\''t'")
    }

    private final class ScriptBox: @unchecked Sendable {
        var script: String?
    }

    func testRunElevatedWithMockRunner() {
        let box = ScriptBox()
        let mockRunner: BrewStorePrivilegeElevationManager.ElevationRunner = { script in
            box.script = script
            return (true, "Installation Succeeded", nil)
        }

        let manager = BrewStorePrivilegeElevationManager(runner: mockRunner)
        let res = manager.runElevated(brewPath: "/opt/homebrew/bin/brew", arguments: ["install", "--cask", "my-app"])

        XCTAssertTrue(res.succeeded)
        XCTAssertEqual(res.output, "Installation Succeeded")
        XCTAssertNil(res.error)

        let script = try? XCTUnwrap(box.script)
        XCTAssertTrue(script?.contains("do shell script") == true)
        XCTAssertTrue(script?.contains("with administrator privileges") == true)
        XCTAssertTrue(script?.contains("/opt/homebrew/bin/brew") == true)
        XCTAssertTrue(script?.contains("install") == true)
        XCTAssertTrue(script?.contains("my-app") == true)
    }

    func testRunElevatedRejectsUnapprovedBinary() {
        let manager = BrewStorePrivilegeElevationManager()
        let res = manager.runElevated(brewPath: "/bin/unapproved_binary", arguments: ["--help"])
        XCTAssertFalse(res.succeeded)
        XCTAssertTrue(res.error?.contains("not permitted") == true)
    }

    func testRunElevatedEscapesNewlinesAndQuotes() {
        let box = ScriptBox()
        let mockRunner: BrewStorePrivilegeElevationManager.ElevationRunner = { script in
            box.script = script
            return (true, "OK", nil)
        }

        let manager = BrewStorePrivilegeElevationManager(runner: mockRunner)
        let res = manager.runElevated(brewPath: "/opt/homebrew/bin/brew", arguments: ["install", "arg\nwith\nnewline", "arg\"quote\""])
        XCTAssertTrue(res.succeeded)

        guard let script = box.script else {
            XCTFail("Script was not captured")
            return
        }

        // Must escape raw newlines to \n to prevent AppleScript syntax syntax errors
        XCTAssertFalse(script.contains("\nwith\n"))
        XCTAssertTrue(script.contains("\\nwith\\n"))
    }
}
