import XCTest
@testable import BrewStore

@MainActor
final class OrphanAndKegAuditorTests: XCTestCase {

    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OrphanKegTests_\(uniqueID)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testKegOnlyPackageItemExportsGeneration() {
        let prefix = "/opt/homebrew/opt/curl"
        let keg = KegOnlyPackageItem(
            id: "curl",
            name: "curl",
            version: "8.12.1",
            isForceLinked: false,
            linkedKeg: nil,
            reasonCode: ":provided_by_macos",
            explanation: "",
            prefixPath: prefix,
            binExists: true,
            libExists: true,
            includeExists: true
        )

        XCTAssertEqual(keg.pathExportSnippet, "export PATH=\"/opt/homebrew/opt/curl/bin:$PATH\"")
        XCTAssertEqual(keg.compilerLdFlagsSnippet, "export LDFLAGS=\"-L/opt/homebrew/opt/curl/lib\"")
        XCTAssertEqual(keg.compilerCppFlagsSnippet, "export CPPFLAGS=\"-I/opt/homebrew/opt/curl/include\"")
        XCTAssertEqual(keg.pkgConfigSnippet, "export PKG_CONFIG_PATH=\"/opt/homebrew/opt/curl/lib/pkgconfig\"")

        let fullSnippet = keg.fullShellSnippet
        XCTAssertTrue(fullSnippet.contains("export PATH=\"/opt/homebrew/opt/curl/bin:$PATH\""))
        XCTAssertTrue(fullSnippet.contains("export LDFLAGS=\"-L/opt/homebrew/opt/curl/lib\""))
        XCTAssertTrue(fullSnippet.contains("export CPPFLAGS=\"-I/opt/homebrew/opt/curl/include\""))
        XCTAssertTrue(fullSnippet.contains("export PKG_CONFIG_PATH=\"/opt/homebrew/opt/curl/lib/pkgconfig\""))
    }

    func testHumanReadableReasonTranslation() {
        let macosProvided = KegOnlyPackageItem(
            id: "curl", name: "curl", version: "8.12.1", isForceLinked: false, linkedKeg: nil,
            reasonCode: ":provided_by_macos", explanation: "", prefixPath: "/opt/curl",
            binExists: true, libExists: false, includeExists: false
        )
        XCTAssertTrue(macosProvided.humanReadableReason.contains("macOS already provides this software"))

        let versioned = KegOnlyPackageItem(
            id: "postgresql@17", name: "postgresql@17", version: "17.11", isForceLinked: true, linkedKeg: "17.11",
            reasonCode: ":versioned_formula", explanation: "", prefixPath: "/opt/postgresql@17",
            binExists: true, libExists: true, includeExists: true
        )
        XCTAssertTrue(versioned.humanReadableReason.contains("versioned formula"))

        let customExp = KegOnlyPackageItem(
            id: "custom", name: "custom", version: "1.0", isForceLinked: false, linkedKeg: nil,
            reasonCode: "other", explanation: "Custom conflict with vendor tool", prefixPath: "/opt/custom",
            binExists: true, libExists: false, includeExists: false
        )
        XCTAssertEqual(customExp.humanReadableReason, "Custom conflict with vendor tool")
    }

    func testPerformAuditScanWithMockExecutor() throws {
        let prefixPath = tempDir.path
        let cellarDir = tempDir.appendingPathComponent("Cellar")
        let optDir = tempDir.appendingPathComponent("opt")

        // Create mock Cellar packages:
        // 1. libpng (orphan)
        let libpngDir = cellarDir.appendingPathComponent("libpng/1.6.43")
        try FileManager.default.createDirectory(at: libpngDir, withIntermediateDirectories: true)
        try "dummy binary".write(to: libpngDir.appendingPathComponent("libpng.dylib"), atomically: true, encoding: .utf8)

        // 2. pcre2 (orphan)
        let pcre2Dir = cellarDir.appendingPathComponent("pcre2/10.42")
        try FileManager.default.createDirectory(at: pcre2Dir, withIntermediateDirectories: true)
        try "dummy pcre2".write(to: pcre2Dir.appendingPathComponent("libpcre2.dylib"), atomically: true, encoding: .utf8)

        // 3. neovim (explicit leaf)
        let nvimDir = cellarDir.appendingPathComponent("neovim/0.10.4")
        try FileManager.default.createDirectory(at: nvimDir, withIntermediateDirectories: true)
        try "dummy nvim".write(to: nvimDir.appendingPathComponent("nvim"), atomically: true, encoding: .utf8)

        // 4. curl (explicit leaf & keg-only)
        let curlDir = cellarDir.appendingPathComponent("curl/8.12.1")
        try FileManager.default.createDirectory(at: curlDir, withIntermediateDirectories: true)
        try "dummy curl".write(to: curlDir.appendingPathComponent("curl"), atomically: true, encoding: .utf8)

        // Create opt/curl directory
        let optCurl = optDir.appendingPathComponent("curl/bin")
        try FileManager.default.createDirectory(at: optCurl, withIntermediateDirectories: true)

        let mockJSON = """
        {
          "formulae": [
            {
              "name": "curl",
              "full_name": "curl",
              "keg_only": true,
              "keg_only_reason": {
                "reason": ":provided_by_macos",
                "explanation": ""
              },
              "linked_keg": null,
              "installed": [{ "version": "8.12.1" }],
              "dependencies": []
            },
            {
              "name": "neovim",
              "full_name": "neovim",
              "keg_only": false,
              "keg_only_reason": null,
              "linked_keg": "0.10.4",
              "installed": [{ "version": "0.10.4" }],
              "dependencies": ["libpng"]
            },
            {
              "name": "libpng",
              "full_name": "libpng",
              "keg_only": false,
              "keg_only_reason": null,
              "linked_keg": "1.6.43",
              "installed": [{ "version": "1.6.43" }],
              "dependencies": []
            },
            {
              "name": "pcre2",
              "full_name": "pcre2",
              "keg_only": false,
              "keg_only_reason": null,
              "linked_keg": "10.42",
              "installed": [{ "version": "10.42" }],
              "dependencies": []
            }
          ]
        }
        """

        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            if arguments == ["leaves", "-p"] {
                return BrewStoreCommandResult(
                    standardOutput: "libpng\npcre2\n",
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
            } else if arguments == ["leaves", "-r"] {
                return BrewStoreCommandResult(
                    standardOutput: "neovim\ncurl\n",
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
            } else if arguments == ["info", "--json=v2", "--installed"] {
                return BrewStoreCommandResult(
                    standardOutput: mockJSON,
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
            return nil
        }

        let mockExecutor = BrewStoreCommandExecutor(customHandler: customHandler)
        let report = OrphanAndKegAuditor.performAuditScan(
            prefix: prefixPath,
            brewPath: "/opt/homebrew/bin/brew",
            executor: mockExecutor
        )

        // Verify orphans
        XCTAssertEqual(report.orphans.count, 2)
        let orphanNames = Set(report.orphans.map(\.name))
        XCTAssertTrue(orphanNames.contains("libpng"))
        XCTAssertTrue(orphanNames.contains("pcre2"))
        XCTAssertGreaterThan(report.totalOrphanBytes, 0)

        // Verify explicit leaves
        XCTAssertEqual(report.explicitLeaves.count, 2)
        let explicitNames = Set(report.explicitLeaves.map(\.name))
        XCTAssertTrue(explicitNames.contains("neovim"))
        XCTAssertTrue(explicitNames.contains("curl"))

        // Verify keg-only package
        XCTAssertEqual(report.kegOnlyPackages.count, 1)
        let curlKeg = report.kegOnlyPackages.first
        XCTAssertEqual(curlKeg?.name, "curl")
        XCTAssertFalse(curlKeg?.isForceLinked ?? true)
        XCTAssertTrue(curlKeg?.binExists ?? false)
    }

    private final class ArgumentBox: @unchecked Sendable {
        var args: [String] = []
    }

    func testToggleKegLinkActions() async {
        let box = ArgumentBox()

        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            box.args = arguments
            return BrewStoreCommandResult(
                standardOutput: "Success",
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
        let auditor = OrphanAndKegAuditor(commandExecutor: executor)

        // Force link
        let forceRes = await auditor.toggleKegLink(packageID: "curl", forceLink: true, prefix: tempDir.path)
        XCTAssertTrue(forceRes.success)
        XCTAssertEqual(box.args, ["link", "--overwrite", "--force", "curl"])

        // Unlink
        let unlinkRes = await auditor.toggleKegLink(packageID: "curl", forceLink: false, prefix: tempDir.path)
        XCTAssertTrue(unlinkRes.success)
        XCTAssertEqual(box.args, ["unlink", "curl"])
    }

    func testPruneSingleOrphanAndPruneAll() async {
        let box = ArgumentBox()

        let customHandler: BrewStoreCommandExecutor.CustomHandler = { _, arguments, _, category, _, _, _ in
            box.args = arguments
            return BrewStoreCommandResult(
                standardOutput: "Pruned",
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
        let auditor = OrphanAndKegAuditor(commandExecutor: executor)

        // Single prune
        let pruneSingleSuccess = await auditor.pruneSingleOrphan(packageID: "libpng", prefix: tempDir.path)
        XCTAssertTrue(pruneSingleSuccess)
        XCTAssertEqual(box.args, ["uninstall", "libpng"])

        // Prune all (autoremove)
        let pruneAllRes = await auditor.pruneAllOrphans(prefix: tempDir.path)
        XCTAssertTrue(pruneAllRes.success)
        XCTAssertEqual(box.args, ["autoremove"])
    }

    func testClipboardCopy() {
        let auditor = OrphanAndKegAuditor(commandExecutor: .shared)
        let testString = "export PATH=\"/opt/homebrew/opt/test/bin:$PATH\""
        auditor.copyToClipboard(testString)

        let pasted = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasted, testString)
    }
}
