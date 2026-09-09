@testable import BrewStore
import XCTest

final class BrewfileTests: XCTestCase {
    func testParsesSupportedBrewfileEntries() {
        let brewfile = BrewStoreBrewfileParser.parse("""
        tap "homebrew/cask"
        brew "git"
        cask "firefox"
        # brew "ignored"
        """)

        XCTAssertEqual(brewfile.taps, ["homebrew/cask"])
        XCTAssertEqual(brewfile.formulae, ["git"])
        XCTAssertEqual(brewfile.casks, ["firefox"])
    }

    func testDiffDoesNotTreatExtraInstalledPackagesAsRemovals() {
        let brewfile = BrewStoreBrewfileParser.parse("brew \"git\"\ncask \"firefox\"")
        let installed = [
            BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "", kind: .formula, applicationNames: [], isInstalled: true, isOutdated: false),
            BrewStorePackage(id: "wget", name: "wget", description: "", homepage: "", version: "", kind: .formula, applicationNames: [], isInstalled: true, isOutdated: false)
        ]
        let diff = BrewStoreBrewfileParser.diff(brewfile, installedPackages: installed, installedTaps: [])

        XCTAssertEqual(diff.missingCasks, ["firefox"])
        XCTAssertEqual(diff.extraInstalledFormulae, ["wget"])
        XCTAssertEqual(diff.changeCount, 1)
    }

    func testGeneratesCustomBrewfile() {
        let packages = [
            BrewStorePackage(id: "visual-studio-code", name: "Visual Studio Code", description: "", homepage: "", version: "1.90.0", kind: .cask, applicationNames: [], isInstalled: true, isOutdated: false),
            BrewStorePackage(id: "ripgrep", name: "ripgrep", description: "", homepage: "", version: "14.1.0", kind: .formula, applicationNames: [], isInstalled: true, isOutdated: false),
            BrewStorePackage(id: "uninstalled-pkg", name: "uninstalled-pkg", description: "", homepage: "", version: "1.0", kind: .formula, applicationNames: [], isInstalled: false, isOutdated: false)
        ]
        let taps = [
            BrewStoreTap(id: "homebrew/cask", name: "homebrew/cask")
        ]

        let generated = BrewStoreBrewfileParser.generate(packages: packages, taps: taps)

        XCTAssertTrue(generated.contains("tap \"homebrew/cask\""))
        XCTAssertTrue(generated.contains("cask \"visual-studio-code\""))
        XCTAssertTrue(generated.contains("brew \"ripgrep\""))
        XCTAssertFalse(generated.contains("uninstalled-pkg"))
    }
}
