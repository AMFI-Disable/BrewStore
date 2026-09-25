@testable import BrewStore
import Foundation
import XCTest

final class CaskQuarantineAuditorTests: XCTestCase {
    func testQuarantineDetailsParsing() {
        let rawStandard = "01c1;6ab3b7ad;;7F633238-DA4C-4253-8A57-5CEE8753AEF8"
        let detailsStandard = QuarantineDetails(rawString: rawStandard)

        XCTAssertEqual(detailsStandard.flags, "01c1")
        XCTAssertNotNil(detailsStandard.timestampDate)
        XCTAssertNil(detailsStandard.agent)
        XCTAssertEqual(detailsStandard.uuid, "7F633238-DA4C-4253-8A57-5CEE8753AEF8")

        let rawHomebrew = "0081;66f3a123;Homebrew;3B98A190-7F2C-4A2B-8A1C-1234567890AB"
        let detailsHomebrew = QuarantineDetails(rawString: rawHomebrew)

        XCTAssertEqual(detailsHomebrew.flags, "0081")
        XCTAssertNotNil(detailsHomebrew.timestampDate)
        XCTAssertEqual(detailsHomebrew.agent, "Homebrew")
        XCTAssertEqual(detailsHomebrew.uuid, "3B98A190-7F2C-4A2B-8A1C-1234567890AB")
        XCTAssertFalse(detailsHomebrew.formattedDate.isEmpty)
    }

    func testSetAndReadQuarantineAttribute() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("quarantine_test_\(UUID().uuidString)")
        try? "app binary dummy content".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let sampleVal = "0081;66f3a123;Homebrew;3B98A190-7F2C-4A2B-8A1C-1234567890AB"
        let setResult = BrewStoreCaskQuarantineAuditor.setQuarantineAttribute(at: tempURL.path, value: sampleVal)
        XCTAssertTrue(setResult)

        let readVal = BrewStoreCaskQuarantineAuditor.readQuarantineAttribute(at: tempURL.path)
        XCTAssertEqual(readVal, sampleVal)
    }

    func testRemoveQuarantineAttribute() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("quarantine_rm_test_\(UUID().uuidString)")
        try? "app binary dummy content".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let sampleVal = "0081;66f3a123;Homebrew;3B98A190-7F2C-4A2B-8A1C-1234567890AB"
        _ = BrewStoreCaskQuarantineAuditor.setQuarantineAttribute(at: tempURL.path, value: sampleVal)
        XCTAssertNotNil(BrewStoreCaskQuarantineAuditor.readQuarantineAttribute(at: tempURL.path))

        let removeResult = BrewStoreCaskQuarantineAuditor.removeQuarantineAttribute(at: tempURL.path, recursive: false)
        XCTAssertTrue(removeResult)

        let postRead = BrewStoreCaskQuarantineAuditor.readQuarantineAttribute(at: tempURL.path)
        XCTAssertNil(postRead)
    }

    func testParseCodesignOutputDeveloperID() {
        let mockOutput = """
        Executable=/Applications/Example.app/Contents/MacOS/Example
        Identifier=com.example.app
        Format=app bundle with Mach-O thin (arm64)
        Authority=Developer ID Application: Example Inc (ABC12345)
        Authority=Developer ID Certification Authority
        Authority=Apple Root CA
        TeamIdentifier=ABC12345
        Sealed Resources version=2 rules=13 files=100
        """

        let result = BrewStoreCaskQuarantineAuditor.parseCodesignOutput(mockOutput)
        XCTAssertTrue(result.isSigned)
        XCTAssertFalse(result.isAdHoc)
        XCTAssertEqual(result.authority, "Developer ID Application: Example Inc (ABC12345)")
        XCTAssertEqual(result.teamID, "ABC12345")
    }

    func testParseCodesignOutputAdHoc() {
        let mockOutput = """
        Executable=/Applications/LocalDev.app/Contents/MacOS/LocalDev
        Identifier=com.local.dev
        Format=app bundle with Mach-O thin (arm64)
        Signature=adhoc
        TeamIdentifier=not set
        Sealed Resources version=2 rules=13 files=10
        """

        let result = BrewStoreCaskQuarantineAuditor.parseCodesignOutput(mockOutput)
        XCTAssertTrue(result.isSigned)
        XCTAssertTrue(result.isAdHoc)
        XCTAssertNil(result.authority)
        XCTAssertNil(result.teamID)
    }

    func testParseCodesignOutputUnsigned() {
        let mockOutput = "/Applications/Unsigned.app: code object is not signed at all"
        let result = BrewStoreCaskQuarantineAuditor.parseCodesignOutput(mockOutput)
        XCTAssertFalse(result.isSigned)
        XCTAssertFalse(result.isAdHoc)
        XCTAssertNil(result.authority)
        XCTAssertNil(result.teamID)
    }

    func testResolveStatus() {
        let quarantined = BrewStoreCaskQuarantineAuditor.resolveStatus(
            isQuarantined: true,
            isSigned: true,
            isAdHoc: false,
            authority: "Developer ID"
        )
        XCTAssertEqual(quarantined, .quarantined)

        let clean = BrewStoreCaskQuarantineAuditor.resolveStatus(
            isQuarantined: false,
            isSigned: true,
            isAdHoc: false,
            authority: "Developer ID"
        )
        XCTAssertEqual(clean, .clean)

        let adHoc = BrewStoreCaskQuarantineAuditor.resolveStatus(
            isQuarantined: false,
            isSigned: true,
            isAdHoc: true,
            authority: nil
        )
        XCTAssertEqual(adHoc, .adHocSigned)

        let invalid = BrewStoreCaskQuarantineAuditor.resolveStatus(
            isQuarantined: false,
            isSigned: false,
            isAdHoc: false,
            authority: nil
        )
        XCTAssertEqual(invalid, .invalidSignature)
    }

    @MainActor
    func testCalculateSummary() {
        let dummyURL = URL(fileURLWithPath: "/Applications/Dummy.app")
        let items: [CaskQuarantineItem] = [
            CaskQuarantineItem(id: "cask1", caskName: "App 1", bundleURL: dummyURL, isQuarantined: true, status: .quarantined),
            CaskQuarantineItem(id: "cask2", caskName: "App 2", bundleURL: dummyURL, isQuarantined: false, status: .clean),
            CaskQuarantineItem(id: "cask3", caskName: "App 3", bundleURL: dummyURL, isQuarantined: false, status: .clean),
            CaskQuarantineItem(id: "cask4", caskName: "App 4", bundleURL: dummyURL, isQuarantined: false, status: .adHocSigned),
            CaskQuarantineItem(id: "cask5", caskName: "App 5", bundleURL: dummyURL, isQuarantined: false, status: .invalidSignature)
        ]

        let auditor = BrewStoreCaskQuarantineAuditor.shared
        let summary = auditor.calculateSummary(for: items)

        XCTAssertEqual(summary.totalAudited, 5)
        XCTAssertEqual(summary.quarantinedCount, 1)
        XCTAssertEqual(summary.cleanCount, 2)
        XCTAssertEqual(summary.adHocCount, 1)
        XCTAssertEqual(summary.invalidCount, 1)
        XCTAssertFalse(summary.isFullyClean)
    }

    @MainActor
    func testAuditPackageNonCaskReturnsNil() async {
        let formula = BrewStorePackage(
            id: "curl",
            name: "curl",
            description: "Command line tool",
            homepage: "https://curl.se",
            version: "8.6.0",
            kind: .formula,
            isInstalled: true
        )

        let auditor = BrewStoreCaskQuarantineAuditor.shared
        let result = await auditor.auditPackage(package: formula)
        XCTAssertNil(result)
    }

    @MainActor
    func testRemoveQuarantineUpdatesState() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("state_test_\(UUID().uuidString)")
        try? "dummy app binary".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        _ = BrewStoreCaskQuarantineAuditor.setQuarantineAttribute(at: tempURL.path, value: "0081;66f3a123;Homebrew;UUID")

        let auditor = BrewStoreCaskQuarantineAuditor.shared
        let item = CaskQuarantineItem(
            id: "test-cask",
            caskName: "Test Cask",
            bundleURL: tempURL,
            isQuarantined: true,
            quarantineDetails: QuarantineDetails(rawString: "0081;66f3a123;Homebrew;UUID"),
            signingAuthority: "Developer ID Application: Test (TEAM)",
            status: .quarantined
        )

        auditor.auditedItems = [item]

        let removeRes = await auditor.removeQuarantine(for: item)
        XCTAssertTrue(removeRes.isSuccess)

        let updated = auditor.auditedItems.first { $0.id == "test-cask" }
        XCTAssertNotNil(updated)
        XCTAssertFalse(updated?.isQuarantined ?? true)
        XCTAssertEqual(updated?.status, .clean)
        XCTAssertNil(updated?.quarantineDetails)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
