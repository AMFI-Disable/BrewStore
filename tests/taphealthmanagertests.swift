@testable import BrewStore
import XCTest

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
}
