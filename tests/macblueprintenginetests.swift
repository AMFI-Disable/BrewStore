@testable import BrewStore
import XCTest

@MainActor
final class MacBlueprintEngineTests: XCTestCase {
    func testBrewfileParsingWithMASApplications() {
        let content = """
        # Test Brewfile
        tap "homebrew/cask"
        brew "git"
        cask "visual-studio-code"
        mas "Xcode", id: 497799835
        mas "Keynote", id: 409183694
        """

        let brewfile = BrewStoreBrewfileParser.parse(content)
        XCTAssertEqual(brewfile.taps.count, 1)
        XCTAssertTrue(brewfile.taps.contains("homebrew/cask"))
        XCTAssertEqual(brewfile.formulae.count, 1)
        XCTAssertTrue(brewfile.formulae.contains("git"))
        XCTAssertEqual(brewfile.casks.count, 1)
        XCTAssertTrue(brewfile.casks.contains("visual-studio-code"))
        XCTAssertEqual(brewfile.masApps.count, 2)
        XCTAssertEqual(brewfile.packageCount, 4) // 1 formula + 1 cask + 2 mas

        let xcodeEntry = brewfile.masApps.first { $0.name == "Xcode" }
        XCTAssertNotNil(xcodeEntry)
        XCTAssertEqual(xcodeEntry?.id, "497799835")
    }

    func testBrewfileGenerationWithMASApplications() {
        let pkg = BrewStorePackage(
            id: "iterm2",
            name: "iTerm2",
            description: "Terminal",
            homepage: "",
            version: "3.5",
            kind: .cask,
            isInstalled: true
        )
        let masApp = MASApp(
            id: "803453959",
            name: "Slack",
            installedVersion: "4.38.0"
        )

        let generated = BrewStoreBrewfileParser.generate(
            packages: [pkg],
            taps: [],
            masApps: [masApp]
        )

        XCTAssertTrue(generated.contains("cask \"iterm2\""))
        XCTAssertTrue(generated.contains("mas \"Slack\", id: 803453959"))
    }

    func testBootstrapScriptGeneration() {
        let bundle = MacRigExportBundle(
            rigName: "Test Rig",
            macModel: "MacBook Pro",
            architecture: "arm64",
            exportDate: Date(),
            taps: ["AMFI-Disable/taps"],
            formulae: [MacRigPackageBundle(name: "ripgrep", version: "14.1.0", kind: "formula", tap: nil)],
            casks: [MacRigPackageBundle(name: "ghostty", version: "1.0", kind: "cask", tap: nil)],
            masApps: [MacRigPackageBundle(name: "Slack", version: "4.38.0", kind: "mas", tap: "803453959")],
            pinnedPackages: ["ripgrep"],
            brewfileContent: ""
        )

        let script = BrewStoreMacTransferManager.shared.generateBootstrapScript(bundle: bundle)
        XCTAssertTrue(script.contains("brew tap AMFI-Disable/taps"))
        XCTAssertTrue(script.contains("brew install ripgrep"))
        XCTAssertTrue(script.contains("brew install --cask ghostty"))
        XCTAssertTrue(script.contains("mas install 803453959 # Slack"))
        XCTAssertTrue(script.contains("brew pin ripgrep"))
    }
}
