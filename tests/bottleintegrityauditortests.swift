import CryptoKit
import XCTest
@testable import BrewStore

@MainActor
final class BottleIntegrityAuditorTests: XCTestCase {

    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BottleIntegrityTests_\(uniqueID)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testComputeFileSHA256() throws {
        let testFile = tempDir.appendingPathComponent("sample.txt")
        let content = "BrewStore Cryptographic Integrity Verification\n"
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let computedHash = BrewStoreBottleIntegrityAuditor.computeFileSHA256(at: testFile)
        XCTAssertNotNil(computedHash)

        // Verify with CryptoKit directly
        let data = content.data(using: .utf8)!
        let expectedHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(computedHash, expectedHash)
    }

    func testParseReceiptJSON() {
        let jsonBottle: [String: Any] = [
            "built_as_bottle": true,
            "poured_from_bottle": true,
            "compiler": "clang",
            "source_modified": false,
            "bottle": [
                "files": [
                    "arm64_sequoia": [
                        "sha256": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
                    ]
                ]
            ]
        ]

        let reportBottle = BrewStoreBottleIntegrityAuditor.parseReceiptJSON(jsonBottle, packageID: "curl", packageName: "curl", version: "8.12.1")
        XCTAssertEqual(reportBottle.status, .verifiedBottle)
        XCTAssertEqual(reportBottle.bottleArch, "arm64_sequoia")
        XCTAssertEqual(reportBottle.bottleSHA256, "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        XCTAssertEqual(reportBottle.compiler, "clang")
        XCTAssertFalse(reportBottle.hasIntegrityIssue)

        let jsonSource: [String: Any] = [
            "built_as_bottle": false,
            "poured_from_bottle": false,
            "compiler": "gcc-14",
            "source_modified": true
        ]

        let reportSource = BrewStoreBottleIntegrityAuditor.parseReceiptJSON(jsonSource, packageID: "htop", packageName: "htop", version: "3.3.0")
        XCTAssertEqual(reportSource.status, .builtFromSource)
        XCTAssertTrue(reportSource.sourceModified)
        XCTAssertEqual(reportSource.compiler, "gcc-14")
        XCTAssertFalse(reportSource.hasIntegrityIssue)
    }

    func testAuditPackageWithMockCellarFiles() throws {
        let prefixPath = tempDir.path
        let cellarDir = tempDir.appendingPathComponent("Cellar")
        let toolDir = cellarDir.appendingPathComponent("ripgrep/14.1.0")
        try FileManager.default.createDirectory(at: toolDir, withIntermediateDirectories: true)

        let binDir = toolDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let binFile = binDir.appendingPathComponent("rg")
        try "binary-mach-o-bytes".write(to: binFile, atomically: true, encoding: .utf8)

        let receiptData = """
        {
          "built_as_bottle": true,
          "poured_from_bottle": true,
          "compiler": "clang",
          "linkage_files": ["bin/rg"]
        }
        """.data(using: .utf8)!
        try receiptData.write(to: toolDir.appendingPathComponent("INSTALL_RECEIPT.json"))

        let sbomData = """
        {
          "packages": [
            {
              "name": "ripgrep",
              "downloadLocation": "https://ghcr.io/v2/homebrew/core/ripgrep/blobs/sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
            }
          ]
        }
        """.data(using: .utf8)!
        try sbomData.write(to: toolDir.appendingPathComponent("sbom.spdx.json"))

        let pkg = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Search tool",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: true,
            installedVersion: "14.1.0"
        )

        let report = BrewStoreBottleIntegrityAuditor.auditPackage(package: pkg, prefix: prefixPath)
        XCTAssertEqual(report.status, .verifiedBottle)
        XCTAssertEqual(report.bottleSHA256, "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210")
        XCTAssertEqual(report.binaryChecksums.count, 1)
        XCTAssertEqual(report.binaryChecksums.first?.relativePath, "bin/rg")
        XCTAssertFalse(report.binaryChecksums.first?.sha256.isEmpty ?? true)
        XCTAssertTrue(report.missingFiles.isEmpty)
        XCTAssertFalse(report.hasIntegrityIssue)
    }

    func testAuditPackageDetectsMissingBinaries() throws {
        let prefixPath = tempDir.path
        let cellarDir = tempDir.appendingPathComponent("Cellar")
        let toolDir = cellarDir.appendingPathComponent("corrupted-tool/1.0.0")
        try FileManager.default.createDirectory(at: toolDir, withIntermediateDirectories: true)

        let receiptData = """
        {
          "built_as_bottle": true,
          "poured_from_bottle": true,
          "linkage_files": ["bin/nonexistent_binary"]
        }
        """.data(using: .utf8)!
        try receiptData.write(to: toolDir.appendingPathComponent("INSTALL_RECEIPT.json"))

        let pkg = BrewStorePackage(
            id: "corrupted-tool",
            name: "corrupted-tool",
            description: "Broken tool",
            homepage: "",
            version: "1.0.0",
            kind: .formula,
            isInstalled: true,
            installedVersion: "1.0.0"
        )

        let report = BrewStoreBottleIntegrityAuditor.auditPackage(package: pkg, prefix: prefixPath)
        XCTAssertEqual(report.status, .corruptedOrTampered)
        XCTAssertTrue(report.hasIntegrityIssue)
        XCTAssertTrue(report.missingFiles.contains("bin/nonexistent_binary"))
        XCTAssertNotNil(report.failureReason)
    }

    func testAuditPackageDetectsTruncatedZeroByteBinary() throws {
        let prefixPath = tempDir.path
        let cellarDir = tempDir.appendingPathComponent("Cellar")
        let toolDir = cellarDir.appendingPathComponent("zero-byte-tool/1.0.0")
        let binDir = toolDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let emptyBinary = binDir.appendingPathComponent("empty_cli")
        FileManager.default.createFile(atPath: emptyBinary.path, contents: Data())

        let receiptData = """
        {
          "built_as_bottle": true,
          "poured_from_bottle": true
        }
        """.data(using: .utf8)!
        try receiptData.write(to: toolDir.appendingPathComponent("INSTALL_RECEIPT.json"))

        let pkg = BrewStorePackage(
            id: "zero-byte-tool",
            name: "zero-byte-tool",
            description: "Zero byte tool",
            homepage: "",
            version: "1.0.0",
            kind: .formula,
            isInstalled: true,
            installedVersion: "1.0.0"
        )

        let report = BrewStoreBottleIntegrityAuditor.auditPackage(package: pkg, prefix: prefixPath)
        XCTAssertEqual(report.status, .corruptedOrTampered)
        XCTAssertTrue(report.hasIntegrityIssue)
        XCTAssertTrue(report.failureReason?.contains("0-byte") ?? false)
    }

    private final class ArgumentBox: @unchecked Sendable {
        var args: [String] = []
    }

    func testReinstallBottleCommandExecution() async {
        let box = ArgumentBox()

        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            box.args = arguments
            return BrewStoreCommandResult(
                standardOutput: "Reinstalled",
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

        let executor = BrewStoreCommandExecutor(customHandler: customHandler)
        let auditor = BrewStoreBottleIntegrityAuditor(commandExecutor: executor)

        let res = await auditor.reinstallBottle(packageID: "wget", prefix: tempDir.path)
        XCTAssertTrue(res.success)
        XCTAssertEqual(box.args, ["reinstall", "--force-bottle", "wget"])
    }
}
