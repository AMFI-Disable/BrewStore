import XCTest
@testable import BrewStore

final class BrewStoreModernizationTests: XCTestCase {

    func testSecurityBoundaryAllowsKillGhAndMo() {
        XCTAssertTrue(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/bin/kill"))
        XCTAssertTrue(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/opt/homebrew/bin/gh"))
        XCTAssertTrue(ExecutionSecurityBoundary.isExecutableAllowed(executablePath: "/opt/homebrew/bin/mo"))
        XCTAssertTrue(ExecutionSecurityBoundary.isExecutableAllowed(
            executablePath: "/Users/test/.homebrew/bin/brew",
            allowedPrefix: "/Users/test/.homebrew"
        ))
    }

    func testPathSafetyValidatorRejectsAllowedRootDirectoryItself() throws {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("brewstore_root_\(UUID().uuidString)", isDirectory: true)
        let child = tmpRoot.appendingPathComponent("AppCache", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let validator = BrewStorePathSafetyValidator(allowedRoots: [tmpRoot])
        XCTAssertNoThrow(try validator.validate(child))
        XCTAssertThrowsError(try validator.validate(tmpRoot)) { error in
            XCTAssertEqual(error as? BrewStorePathSafetyError, .outsideAllowedRoots(tmpRoot))
        }
    }

    func testCommandExecutorDeliversStandardInputWithoutShell() {
        let result = BrewStoreCommandExecutor.shared.run(
            executablePath: "/bin/cat",
            arguments: [],
            timeout: 5,
            category: .readOnly,
            standardInput: Data("hello-stdin".utf8)
        )
        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.standardOutput, "hello-stdin")
    }
}
