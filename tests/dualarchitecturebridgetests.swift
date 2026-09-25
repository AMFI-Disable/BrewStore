import XCTest
@testable import BrewStore

@MainActor
final class DualArchitectureBridgeTests: XCTestCase {

    var tempDir: URL!
    var bridgeManager: DualArchitectureBridgeManager!

    override func setUp() async throws {
        try await super.setUp()
        let uniqueID = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DualArchTests_\(uniqueID)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bridgeManager = DualArchitectureBridgeManager(commandExecutor: .shared)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testHostHardwareArchitectureDetection() {
        let arch = DualArchitectureBridgeManager.detectHostArchitecture()
        XCTAssertNotEqual(arch, .unknown)
        #if arch(arm64)
        XCTAssertEqual(arch, .arm64)
        XCTAssertTrue(arch.isAppleSilicon)
        #else
        XCTAssertEqual(arch, .x86_64)
        XCTAssertFalse(arch.isAppleSilicon)
        #endif
    }

    func testRosettaStatusDetectionOnHost() {
        let hostArch = DualArchitectureBridgeManager.detectHostArchitecture()
        let rosetta = DualArchitectureBridgeManager.detectRosettaStatus(
            hostArch: hostArch,
            fileManager: .default,
            executor: .shared
        )

        if hostArch == .arm64 {
            XCTAssertTrue(rosetta.isSupported)
            XCTAssertFalse(rosetta.statusDescription.isEmpty)
        } else {
            XCTAssertFalse(rosetta.isSupported)
            XCTAssertFalse(rosetta.isInstalled)
        }
    }

    func testPrefixProfileScanningWithSimulatedCellar() throws {
        let fm = FileManager.default
        let prefixPath = tempDir.path

        // 1. Create bin/brew executable
        let binDir = tempDir.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        let brewScript = binDir.appendingPathComponent("brew")
        try "#!/bin/sh\necho 'Homebrew 4.4.0'\n".write(to: brewScript, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brewScript.path)

        // 2. Create Cellar with 2 formulae
        let cellarDir = tempDir.appendingPathComponent("Cellar", isDirectory: true)
        let nodeDir = cellarDir.appendingPathComponent("node/20.0.0", isDirectory: true)
        let rgDir = cellarDir.appendingPathComponent("ripgrep/14.0.0", isDirectory: true)
        try fm.createDirectory(at: nodeDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: rgDir, withIntermediateDirectories: true)

        // Add dummy binaries
        try "dummy binary content".write(to: nodeDir.appendingPathComponent("node"), atomically: true, encoding: .utf8)
        try "dummy rg content".write(to: rgDir.appendingPathComponent("rg"), atomically: true, encoding: .utf8)

        // 3. Create Caskroom with 1 cask
        let caskDir = tempDir.appendingPathComponent("Caskroom", isDirectory: true)
        let itermDir = caskDir.appendingPathComponent("iterm2/3.5.0", isDirectory: true)
        try fm.createDirectory(at: itermDir, withIntermediateDirectories: true)

        let profile = DualArchitectureBridgeManager.scanPrefixProfile(
            prefixPath: prefixPath,
            prefixName: "Test Prefix",
            targetArch: .appleSilicon,
            hostArch: .arm64,
            activeBrewPath: brewScript.path,
            fileManager: fm,
            executor: .shared
        )

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.formulaCount, 2)
        XCTAssertEqual(profile?.caskCount, 1)
        XCTAssertEqual(profile?.totalPackagesCount, 3)
        XCTAssertTrue(profile?.prefix.isActive ?? false)

        let packageIDs = Set(profile?.packages.map(\.packageID) ?? [])
        XCTAssertTrue(packageIDs.contains("node"))
        XCTAssertTrue(packageIDs.contains("ripgrep"))
        XCTAssertTrue(packageIDs.contains("iterm2"))
    }

    func testDualArchitectureComparisonLogic() {
        let armPackages = [
            CrossArchPackageItem(packageID: "node", name: "Node.js", kind: .formula, installedVersion: "20.10.0", prefixPath: "/opt/homebrew", architecture: .appleSilicon, isNativeToHost: true, binaryPath: nil),
            CrossArchPackageItem(packageID: "git", name: "Git", kind: .formula, installedVersion: "2.44.0", prefixPath: "/opt/homebrew", architecture: .appleSilicon, isNativeToHost: true, binaryPath: nil),
            CrossArchPackageItem(packageID: "wget", name: "wget", kind: .formula, installedVersion: "1.24.0", prefixPath: "/opt/homebrew", architecture: .appleSilicon, isNativeToHost: true, binaryPath: nil)
        ]

        let armProfile = PrefixArchitectureProfile(
            prefix: HomebrewPrefix(id: "/opt/homebrew", name: "Apple Silicon", brewExecutablePath: "/opt/homebrew/bin/brew", architecture: .appleSilicon, isAvailable: true, isActive: true),
            homebrewVersion: "Homebrew 4.4.0",
            formulaCount: 3,
            caskCount: 0,
            diskUsageBytes: 50_000_000,
            packages: armPackages
        )

        let intelPackages = [
            CrossArchPackageItem(packageID: "node", name: "Node.js", kind: .formula, installedVersion: "18.15.0", prefixPath: "/usr/local", architecture: .intel, isNativeToHost: false, binaryPath: nil),
            CrossArchPackageItem(packageID: "python@3.9", name: "Python 3.9", kind: .formula, installedVersion: "3.9.18", prefixPath: "/usr/local", architecture: .intel, isNativeToHost: false, binaryPath: nil),
            CrossArchPackageItem(packageID: "legacy-client", name: "Legacy Client", kind: .cask, installedVersion: "1.0", prefixPath: "/usr/local", architecture: .intel, isNativeToHost: false, binaryPath: nil)
        ]

        let intelProfile = PrefixArchitectureProfile(
            prefix: HomebrewPrefix(id: "/usr/local", name: "Intel", brewExecutablePath: "/usr/local/bin/brew", architecture: .intel, isAvailable: true, isActive: false),
            homebrewVersion: "Homebrew 4.4.0",
            formulaCount: 2,
            caskCount: 1,
            diskUsageBytes: 30_000_000,
            packages: intelPackages
        )

        let rosetta = RosettaStatus(isSupported: true, isInstalled: true, isRunningDaemon: true)

        let comp = DualArchitectureBridgeManager.buildComparison(
            hostArch: .arm64,
            rosetta: rosetta,
            activePrefix: "/opt/homebrew",
            arm64Profile: armProfile,
            intelProfile: intelProfile,
            translatedDaemons: []
        )

        XCTAssertTrue(comp.isDualPrefixInstalled)
        XCTAssertTrue(comp.hasDualInstalledDuplicates)
        XCTAssertTrue(comp.hasRosettaOnlyPackages)

        // Dual installed: "node"
        XCTAssertEqual(comp.dualInstalledPackages.count, 1)
        XCTAssertEqual(comp.dualInstalledPackages.first?.packageID, "node")
        XCTAssertEqual(comp.dualInstalledPackages.first?.arm64Version, "20.10.0")
        XCTAssertEqual(comp.dualInstalledPackages.first?.intelVersion, "18.15.0")
        XCTAssertFalse(comp.dualInstalledPackages.first?.isIdenticalVersion ?? true)

        // ARM64 only: "git", "wget"
        let armOnlyIDs = Set(comp.arm64OnlyPackages.map(\.packageID))
        XCTAssertEqual(armOnlyIDs, Set(["git", "wget"]))

        // Intel only: "legacy-client", "python@3.9"
        let intelOnlyIDs = Set(comp.intelOnlyPackages.map(\.packageID))
        XCTAssertEqual(intelOnlyIDs, Set(["legacy-client", "python@3.9"]))
    }

    func testBootstrapAndInstallCommands() {
        let rosettaCmd = DualArchitectureBridgeManager.rosettaInstallCommand
        XCTAssertTrue(rosettaCmd.contains("softwareupdate"))
        XCTAssertTrue(rosettaCmd.contains("--install-rosetta"))

        let intelCmd = DualArchitectureBridgeManager.intelBrewBootstrapCommand
        XCTAssertTrue(intelCmd.contains("arch -x86_64"))
        XCTAssertTrue(intelCmd.contains("install.sh"))
    }
}
