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

    func testBackupFrequencyIntervals() {
        XCTAssertEqual(SnapshotBackupFrequency.manual.intervalSeconds, 0)
        XCTAssertEqual(SnapshotBackupFrequency.daily.intervalSeconds, 86400)
        XCTAssertEqual(SnapshotBackupFrequency.weekly.intervalSeconds, 604800)
        XCTAssertEqual(SnapshotBackupFrequency.monthly.intervalSeconds, 2592000)
    }

    @MainActor
    func testScheduledBackupTriggering() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let snapshotManager = BrewStoreSnapshotManager(directory: tempDir)
        snapshotManager.backupFrequency = .daily
        snapshotManager.lastScheduledBackupDate = nil

        let homebrewManager = HomebrewManager()

        XCTAssertTrue(snapshotManager.snapshots.isEmpty)

        snapshotManager.checkScheduledBackup(manager: homebrewManager)
        XCTAssertEqual(snapshotManager.snapshots.count, 1)

        snapshotManager.checkScheduledBackup(manager: homebrewManager)
        XCTAssertEqual(snapshotManager.snapshots.count, 1)
    }

    @MainActor
    func testWishlistManagerExportToBrewfileHandlesUninstalledCasks() {
        let wishlistManager = BrewStoreWishlistManager.shared
        let manager = HomebrewManager()
        let result = wishlistManager.exportToBrewfile(
            packageIDs: ["ripgrep", "google-chrome"],
            manager: manager,
            knownCaskIDs: ["google-chrome"]
        )

        XCTAssertTrue(result.contains("cask \"google-chrome\""))
        XCTAssertTrue(result.contains("brew \"ripgrep\""))
    }

    @MainActor
    func testBrewfileImporterParsesComplexRubyOptionsAndComments() {
        let content = """
        # Global taps
        tap 'homebrew/cask-fonts'
        brew "postgresql@16", restart_service: :changed
        cask 'font-fira-code', args: { no_quarantine: true }
        mas "Xcode", id: 497799835 # Developer suite
        mas 'Amphetamine', id: 937984704, option: true
        """
        let manager = HomebrewManager()
        let summary = BrewStoreBrewfileImporter.shared.parseBrewfile(content: content, manager: manager)

        XCTAssertEqual(summary.taps, ["homebrew/cask-fonts"])
        XCTAssertEqual(summary.formulae.map(\.rawName), ["postgresql@16"])
        XCTAssertEqual(summary.casks.map(\.rawName), ["font-fira-code"])
        XCTAssertEqual(summary.masApps.count, 2)
        XCTAssertEqual(summary.masApps[0].rawName, "Xcode")
        XCTAssertEqual(summary.masApps[0].id, "mas:497799835")
        XCTAssertEqual(summary.masApps[1].rawName, "Amphetamine")
        XCTAssertEqual(summary.masApps[1].id, "mas:937984704")
    }

    @MainActor
    func testSnapshotDiffComputesMissingTaps() {
        let snapshot = BrewStoreSnapshot(
            id: "snap-1",
            timestamp: Date(),
            name: "Test Snapshot",
            fileURL: URL(fileURLWithPath: "/tmp/Brewfile-1"),
            formulae: ["git"],
            casks: ["firefox"],
            taps: ["homebrew/cask-fonts", "custom/tap"]
        )
        let installedPackages = [
            BrewStorePackage(id: "git", name: "git", description: "", homepage: "", version: "2.45.0", kind: .formula, isInstalled: true, isOutdated: false),
            BrewStorePackage(id: "firefox", name: "firefox", description: "", homepage: "", version: "128.0", kind: .cask, isInstalled: true, isOutdated: false)
        ]
        let installedTaps = [
            BrewStoreTap(id: "homebrew/cask-fonts", name: "homebrew/cask-fonts")
        ]

        let diff = BrewStoreSnapshotManager().computeDiff(for: snapshot, currentPackages: installedPackages, currentTaps: installedTaps)
        XCTAssertTrue(diff.hasDifferences, "Missing tap must trigger hasDifferences")
        XCTAssertEqual(diff.missingTaps, ["custom/tap"])
        XCTAssertEqual(diff.missingFormulae, [])
        XCTAssertEqual(diff.missingCasks, [])
        XCTAssertEqual(diff.totalChanges, 1)
    }

    @MainActor
    func testSnapshotRollbackPlanPreservesCasksAndTaps() {
        let snapshot = BrewStoreSnapshot(
            id: "snap-2",
            timestamp: Date(),
            name: "Test Snapshot 2",
            fileURL: URL(fileURLWithPath: "/tmp/Brewfile-2"),
            formulae: ["wget"],
            casks: ["visual-studio-code"],
            taps: ["hashicorp/tap"]
        )
        let currentPackages: [BrewStorePackage] = []
        let currentTaps: [BrewStoreTap] = []

        let plan = BrewStoreSnapshotRollbackManager.shared.computePlan(
            currentPackages: currentPackages,
            currentTaps: currentTaps,
            snapshot: snapshot
        )

        XCTAssertEqual(plan.packagesToReinstall, ["visual-studio-code", "wget"])
        XCTAssertEqual(plan.missingTaps, ["hashicorp/tap"])
        XCTAssertTrue(plan.caskIDs.contains("visual-studio-code"))
        XCTAssertFalse(plan.caskIDs.contains("wget"))
        XCTAssertEqual(plan.totalOperations, 3)
    }
}
