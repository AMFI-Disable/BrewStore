@testable import BrewStore
import Foundation
import XCTest

final class SourceBuildStudioTests: XCTestCase {
    func testParseClangVersion() {
        let mockOutput = """
        Apple clang version 21.0.0 (clang-2100.3.25.1)
        Target: arm64-apple-darwin27.2.0
        Thread model: posix
        InstalledDir: /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
        """

        let result = BrewStoreSourceBuildManager.parseClangVersion(mockOutput)
        XCTAssertEqual(result.version, "21.0.0 (clang-2100.3.25.1)")
        XCTAssertEqual(result.target, "arm64-apple-darwin27.2.0")
    }

    func testFindGCCCompilers() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("gcc_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create mock binaries
        let gcc14 = tempDir.appendingPathComponent("gcc-14")
        let gcc16 = tempDir.appendingPathComponent("gcc-16")
        let gccAr = tempDir.appendingPathComponent("gcc-ar-14")
        let gccNm = tempDir.appendingPathComponent("gcc-nm-16")
        let clang = tempDir.appendingPathComponent("clang")

        try? "".write(to: gcc14, atomically: true, encoding: .utf8)
        try? "".write(to: gcc16, atomically: true, encoding: .utf8)
        try? "".write(to: gccAr, atomically: true, encoding: .utf8)
        try? "".write(to: gccNm, atomically: true, encoding: .utf8)
        try? "".write(to: clang, atomically: true, encoding: .utf8)

        let found = BrewStoreSourceBuildManager.findGCCCompilers(in: [tempDir.path])
        XCTAssertEqual(found, ["gcc-16", "gcc-14"])
    }

    func testSourceBuildConfigArguments() {
        let formula = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Fast line-oriented search tool",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: false
        )

        var config = SourceBuildConfig()
        config.buildFromSource = true
        config.head = false
        config.verbose = false
        config.selectedCompiler = nil

        var args = config.generateArguments(for: formula)
        XCTAssertEqual(args, ["install", "--build-from-source", "ripgrep"])

        config.head = true
        config.fetchHead = true
        config.selectedCompiler = "gcc-16"
        config.verbose = true
        config.customArgs = "--debug"

        args = config.generateArguments(for: formula)
        XCTAssertTrue(args.contains("--build-from-source"))
        XCTAssertTrue(args.contains("--HEAD"))
        XCTAssertTrue(args.contains("--fetch-HEAD"))
        XCTAssertTrue(args.contains("--cc=gcc-16"))
        XCTAssertTrue(args.contains("--verbose"))
        XCTAssertTrue(args.contains("--debug"))
        XCTAssertEqual(args.last, "ripgrep")

        // Test with installed package (uses reinstall)
        let installedFormula = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Fast line-oriented search tool",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: true
        )

        let reinstallArgs = config.generateArguments(for: installedFormula)
        XCTAssertEqual(reinstallArgs.first, "reinstall")
    }

    func testDetectErrorsInLogContent() {
        let cleanLog = """
        [1/5] Compiling main.c...
        [2/5] Compiling util.c...
        [3/5] Linking libexample.dylib...
        Build complete.
        """

        let (hasErr1, errLines1) = BrewStoreSourceBuildManager.detectErrors(in: cleanLog)
        XCTAssertFalse(hasErr1)
        XCTAssertTrue(errLines1.isEmpty)

        let failureLog = """
        [1/5] Compiling main.c...
        main.c:42:10: fatal error: 'openssl/ssl.h' file not found
        #include <openssl/ssl.h>
                 ^~~~~~~~~~~~~~~
        1 error generated.
        make: *** [all] Error 2
        """

        let (hasErr2, errLines2) = BrewStoreSourceBuildManager.detectErrors(in: failureLog)
        XCTAssertTrue(hasErr2)
        XCTAssertEqual(errLines2.count, 3)
        XCTAssertTrue(errLines2.contains { $0.contains("fatal error:") })
        XCTAssertTrue(errLines2.contains { $0.contains("1 error generated.") })
        XCTAssertTrue(errLines2.contains { $0.contains("make: ***") })
    }

    func testBuildLogFileFormatting() {
        let dummyURL = URL(fileURLWithPath: "/tmp/01.configure")
        let now = Date()
        let log = BuildLogFile(
            name: "01.configure",
            formulaName: "openssl",
            url: dummyURL,
            modificationDate: now,
            sizeInBytes: 1024 * 50,
            hasErrors: false,
            errorLines: [],
            contentPreview: "configure output preview"
        )

        XCTAssertEqual(log.id, "openssl:01.configure")
        XCTAssertFalse(log.formattedSize.isEmpty)
        XCTAssertFalse(log.formattedDate.isEmpty)
        XCTAssertFalse(log.hasErrors)
    }

    func testCompilerToolchainInfoReadyStatus() {
        let readyInfo = CompilerToolchainInfo(
            hasCommandLineTools: true,
            commandLineToolsPath: "/Library/Developer/CommandLineTools",
            clangVersion: "15.0.0",
            clangTarget: "arm64-apple-darwin23.0.0",
            cmakeVersion: "3.28.0",
            makeVersion: "3.81",
            ninjaVersion: "1.11.1",
            availableGCCs: ["gcc-14"],
            detectedDate: Date()
        )

        XCTAssertTrue(readyInfo.isReadyForCompilation)
        XCTAssertTrue(readyInfo.defaultCompilerDisplayName.contains("Apple Clang"))

        let notReadyInfo = CompilerToolchainInfo(
            hasCommandLineTools: false,
            commandLineToolsPath: nil,
            clangVersion: nil,
            clangTarget: nil,
            cmakeVersion: nil,
            makeVersion: nil,
            ninjaVersion: nil,
            availableGCCs: [],
            detectedDate: Date()
        )

        XCTAssertFalse(notReadyInfo.isReadyForCompilation)
        XCTAssertEqual(notReadyInfo.defaultCompilerDisplayName, "System Default")
    }
}
