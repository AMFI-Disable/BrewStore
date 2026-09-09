@testable import BrewStore
import Foundation
import XCTest

final class TCCPermissionManagerTests: XCTestCase {
    func testDetectSystemExtensions() {
        let pkg = BrewStorePackage(
            id: "docker",
            name: "Docker",
            description: "App container platform",
            homepage: "https://docker.com",
            version: "4.30.0",
            kind: .cask,
            caveats: "Docker installs a system extension for privileged networking."
        )

        let perms = TCCPermissionManager.shared.detectPermissions(for: pkg)
        XCTAssertTrue(perms.contains(.systemExtensions))
    }

    func testDetectAccessibility() {
        let pkg = BrewStorePackage(
            id: "betterdisplay",
            name: "BetterDisplay",
            description: "Display management tool",
            homepage: "https://example.com",
            version: "2.3.0",
            kind: .cask,
            caveats: "Requires Accessibility authorization to control screen brightness and DDC."
        )

        let perms = TCCPermissionManager.shared.detectPermissions(for: pkg)
        XCTAssertTrue(perms.contains(.accessibility))
    }

    func testFormulaDoesNotRequireTCC() {
        let pkg = BrewStorePackage(
            id: "git",
            name: "git",
            description: "Version control",
            homepage: "https://git-scm.com",
            version: "2.45.0",
            kind: .formula,
            caveats: "system extension"
        )

        let perms = TCCPermissionManager.shared.detectPermissions(for: pkg)
        XCTAssertTrue(perms.isEmpty, "CLI formula should not be assigned GUI TCC permissions")
    }

    func testSettingsURLStrings() {
        for perm in TCCPermissionKind.allCases {
            XCTAssertTrue(perm.settingsURLString.hasPrefix("x-apple.systempreferences:com.apple.preference.security"))
            XCTAssertFalse(perm.explanation.isEmpty)
            XCTAssertFalse(perm.systemImage.isEmpty)
        }
    }
}
