@testable import BrewStore
import XCTest

@MainActor
final class CLIToolManagerTests: XCTestCase {
    func testCLIToolManagerBundledScriptOrWorkspaceExists() {
        let manager = BrewStoreCLIToolManager.shared
        // In local test runs, either bundled script or fallback workspace script must resolve
        let scriptPath = manager.bundledScriptPath
        XCTAssertNotNil(scriptPath, "bundledScriptPath should locate brewstore companion script")
        if let path = scriptPath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Target script file must exist on disk at \(path)")
        }
    }

    func testZshCompletionGeneration() {
        let zshScript = BrewStoreCLIToolManager.generateZshCompletion()
        XCTAssertTrue(zshScript.contains("#compdef brewstore"))
        XCTAssertTrue(zshScript.contains("devclean"))
        XCTAssertTrue(zshScript.contains("blueprint"))
        XCTAssertTrue(zshScript.contains("completions"))
        XCTAssertTrue(zshScript.contains("install-cli"))
    }

    func testBashCompletionGeneration() {
        let bashScript = BrewStoreCLIToolManager.generateBashCompletion()
        XCTAssertTrue(bashScript.contains("_brewstore_completions"))
        XCTAssertTrue(bashScript.contains("complete -F _brewstore_completions brewstore"))
        XCTAssertTrue(bashScript.contains("devclean"))
        XCTAssertTrue(bashScript.contains("blueprint"))
    }

    func testFishCompletionGeneration() {
        let fishScript = BrewStoreCLIToolManager.generateFishCompletion()
        XCTAssertTrue(fishScript.contains("complete -c brewstore"))
        XCTAssertTrue(fishScript.contains("devclean"))
        XCTAssertTrue(fishScript.contains("blueprint"))
        XCTAssertTrue(fishScript.contains("install-cli"))
    }

    func testPrimaryAndFallbackInstallPaths() {
        let manager = BrewStoreCLIToolManager.shared
        XCTAssertTrue(manager.primaryInstallPath.contains(".local/bin/brewstore"))
        XCTAssertEqual(manager.fallbackInstallPath, "/usr/local/bin/brewstore")
    }

    func testCLISymlinkLifecycleInTemporaryDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dummySource = tempDir.appendingPathComponent("brewstore-src")
        try "#!/bin/bash\necho ok\n".write(to: dummySource, atomically: true, encoding: .utf8)

        let targetSymlink = tempDir.appendingPathComponent("brewstore-link")
        try FileManager.default.createSymbolicLink(at: targetSymlink, withDestinationURL: dummySource)

        XCTAssertTrue(FileManager.default.fileExists(atPath: targetSymlink.path))
        let dest = try FileManager.default.destinationOfSymbolicLink(atPath: targetSymlink.path)
        XCTAssertEqual(dest, dummySource.path)
    }
}
