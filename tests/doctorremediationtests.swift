@testable import BrewStore
import XCTest

final class DoctorRemediationTests: XCTestCase {
    @MainActor
    func testCleanDoctorOutputYieldsEmptyOrSuggestionOnly() {
        let manager = BrewStoreDoctorRemediationManager.shared
        let cleanOutput = "Your system is ready to brew."
        let issues = manager.analyzeIssues(rawDoctorOutput: cleanOutput, packages: [])

        XCTAssertTrue(issues.isEmpty)
    }

    @MainActor
    func testDoctorOutputWithWarningsParsesActionableIssues() {
        let manager = BrewStoreDoctorRemediationManager.shared
        let warningOutput = """
        Warning: You have unlinked kegs in your Cellar.
        Leaving kegs unlinked can resolve in broken builds.
        """

        let issues = manager.analyzeIssues(rawDoctorOutput: warningOutput, packages: [])
        XCTAssertFalse(issues.isEmpty)

        let unlinkedIssue = issues.first { $0.id == "unlinked_kegs" }
        XCTAssertNotNil(unlinkedIssue)
        XCTAssertEqual(unlinkedIssue?.severity, .warning)
        XCTAssertEqual(unlinkedIssue?.fixCommandArgs, ["cleanup", "--prune=all"])
    }

    @MainActor
    func testMissingDependenciesDetection() {
        let manager = BrewStoreDoctorRemediationManager.shared
        let pkg = BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "", homepage: "", version: "14.0", kind: .formula, isInstalled: true, dependencies: ["pcre2"])
        let issues = manager.analyzeIssues(rawDoctorOutput: "Warning: broken symlinks", packages: [pkg])

        let missingIssue = issues.first { $0.id == "missing_deps" }
        XCTAssertNotNil(missingIssue)
        XCTAssertTrue(missingIssue?.description.contains("pcre2") == true)
    }
}
