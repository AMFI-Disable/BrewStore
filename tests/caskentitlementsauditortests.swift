import XCTest
@testable import BrewStore

final class CaskEntitlementsAuditorTests: XCTestCase {

    func testParseMalformedOrEmptyXML() {
        let emptyResult = CaskEntitlementsAuditor.parseEntitlementsPlist(from: "")
        XCTAssertTrue(emptyResult.isEmpty)

        let plainText = "Executable=/bin/ls\ncode object is not signed at all"
        let plainResult = CaskEntitlementsAuditor.parseEntitlementsPlist(from: plainText)
        XCTAssertTrue(plainResult.isEmpty)
    }

    func testParseValidEntitlementsXML() {
        let sampleXML = """
        Executable=/Applications/Sample.app/Contents/MacOS/Sample
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.security.app-sandbox</key>
            <true/>
            <key>com.apple.security.network.client</key>
            <true/>
            <key>com.apple.security.device.camera</key>
            <true/>
            <key>com.apple.security.device.microphone</key>
            <true/>
        </dict>
        </plist>
        """

        let parsed = CaskEntitlementsAuditor.parseEntitlementsPlist(from: sampleXML)
        XCTAssertEqual(parsed["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(parsed["com.apple.security.network.client"] as? Bool, true)
        XCTAssertEqual(parsed["com.apple.security.device.camera"] as? Bool, true)
        XCTAssertEqual(parsed["com.apple.security.device.microphone"] as? Bool, true)
    }

    func testGenerateReportWithSecurityBadges() {
        let entitlements: [String: Any] = [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.device.camera": true,
            "com.apple.security.files.all": true,
            "com.apple.security.cs.allow-jit": true
        ]

        let report = CaskEntitlementsAuditor.generateReport(
            packageID: "test-cask",
            applicationPath: "/Applications/Test.app",
            entitlements: entitlements,
            isHardenedRuntime: true
        )

        XCTAssertTrue(report.isSandboxed)
        XCTAssertTrue(report.isHardenedRuntime)
        XCTAssertTrue(report.hasCameraAccess)
        XCTAssertTrue(report.hasFullDiskAccess)
        XCTAssertTrue(report.allowsJIT)
        XCTAssertEqual(report.securitySummary, "App Sandbox Enforced")

        let badgeIDs = report.badges.map(\.id)
        XCTAssertTrue(badgeIDs.contains("sandbox"))
        XCTAssertTrue(badgeIDs.contains("hardened_runtime"))
        XCTAssertTrue(badgeIDs.contains("camera"))
        XCTAssertTrue(badgeIDs.contains("full_disk"))
        XCTAssertTrue(badgeIDs.contains("allow_jit"))
    }

    func testRelaxedSecuritySummary() {
        let entitlements: [String: Any] = [
            "com.apple.security.cs.disable-library-validation": true
        ]

        let report = CaskEntitlementsAuditor.generateReport(
            packageID: "relaxed-cask",
            applicationPath: "/Applications/Relaxed.app",
            entitlements: entitlements,
            isHardenedRuntime: false
        )

        XCTAssertFalse(report.isSandboxed)
        XCTAssertTrue(report.disablesLibraryValidation)
        XCTAssertEqual(report.securitySummary, "Relaxed Security Flags")
    }
}
