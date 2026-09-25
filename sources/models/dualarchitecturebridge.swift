import AppKit
import Foundation

// MARK: - Core Architecture Models

enum HostHardwareArchitecture: String, Codable, Hashable, Sendable {
    case arm64 = "Apple Silicon (ARM64)"
    case x86_64 = "Intel (x86_64)"
    case unknown = "Unknown Architecture"

    var isAppleSilicon: Bool {
        self == .arm64
    }

    var badgeColor: String {
        switch self {
        case .arm64: "purple"
        case .x86_64: "blue"
        case .unknown: "secondary"
        }
    }
}

struct RosettaStatus: Codable, Hashable, Sendable {
    let isSupported: Bool
    let isInstalled: Bool
    let isRunningDaemon: Bool

    var statusDescription: String {
        guard isSupported else { return "Not Applicable (Native Intel Mac)" }
        if isInstalled {
            return isRunningDaemon ? "Active (Translation Engine Running)" : "Ready (Rosetta 2 Installed)"
        } else {
            return "Not Installed"
        }
    }

    var badgeColor: String {
        if !isSupported { return "secondary" }
        return isInstalled ? "green" : "orange"
    }
}

struct CrossArchPackageItem: Identifiable, Hashable, Sendable {
    var id: String { "\(prefixPath):\(packageID)" }
    let packageID: String
    let name: String
    let kind: BrewPackageKind
    let installedVersion: String
    let prefixPath: String
    let architecture: BinaryArchitectureType
    let isNativeToHost: Bool
    let binaryPath: String?
}

struct DualPackageComparison: Identifiable, Hashable, Sendable {
    var id: String { packageID }
    let packageID: String
    let name: String
    let kind: BrewPackageKind
    let arm64Version: String
    let intelVersion: String
    let arm64Path: String
    let intelPath: String
    let isIdenticalVersion: Bool
}

struct TranslatedDaemonItem: Identifiable, Hashable, Sendable {
    var id: String { "\(serviceName):\(pid)" }
    let serviceName: String
    let pid: Int32
    let isTranslated: Bool
    let architecture: BinaryArchitectureType
    let executablePath: String?
}

struct PrefixArchitectureProfile: Identifiable, Hashable, Sendable {
    var id: String { prefix.id }
    let prefix: HomebrewPrefix
    let homebrewVersion: String?
    let formulaCount: Int
    let caskCount: Int
    let diskUsageBytes: Int64
    let packages: [CrossArchPackageItem]

    var totalPackagesCount: Int {
        formulaCount + caskCount
    }

    var formattedDiskUsage: String {
        ByteCountFormatter.string(fromByteCount: diskUsageBytes, countStyle: .file)
    }
}

struct DualArchitectureComparison: Hashable, Sendable {
    let hostArchitecture: HostHardwareArchitecture
    let rosettaStatus: RosettaStatus
    let activePrefixPath: String?
    let arm64Profile: PrefixArchitectureProfile?
    let intelProfile: PrefixArchitectureProfile?
    let dualInstalledPackages: [DualPackageComparison]
    let arm64OnlyPackages: [CrossArchPackageItem]
    let intelOnlyPackages: [CrossArchPackageItem]
    let translatedDaemons: [TranslatedDaemonItem]

    var isDualPrefixInstalled: Bool {
        arm64Profile?.prefix.isAvailable == true && intelProfile?.prefix.isAvailable == true
    }

    var hasRosettaOnlyPackages: Bool {
        !intelOnlyPackages.isEmpty
    }

    var hasDualInstalledDuplicates: Bool {
        !dualInstalledPackages.isEmpty
    }
}

// MARK: - Dual Architecture Bridge Manager

@MainActor
final class DualArchitectureBridgeManager: ObservableObject {
    static let shared = DualArchitectureBridgeManager()

    @Published var comparison: DualArchitectureComparison?
    @Published var isScanning = false
    @Published var operationStatus: String?
    @Published var isPerformingOperation = false

    private let fileManager: FileManager
    private let commandExecutor: BrewStoreCommandExecutor

    init(
        fileManager: FileManager = .default,
        commandExecutor: BrewStoreCommandExecutor = .shared
    ) {
        self.fileManager = fileManager
        self.commandExecutor = commandExecutor
    }

    // MARK: - Scanning & Analysis

    func scanDualArchitectureEnvironment(activeManager: HomebrewManager) async {
        isScanning = true
        defer { isScanning = false }

        let activePath = activeManager.brewPrefix
        let activeBrew = activeManager.brewPath
        let services = activeManager.services

        let comp = await Task.detached(priority: .userInitiated) { [fileManager, commandExecutor] in
            let hostArch = Self.detectHostArchitecture()
            let rosetta = Self.detectRosettaStatus(hostArch: hostArch, fileManager: fileManager, executor: commandExecutor)

            let armProfile = Self.scanPrefixProfile(
                prefixPath: "/opt/homebrew",
                prefixName: "Apple Silicon (ARM64)",
                targetArch: .appleSilicon,
                hostArch: hostArch,
                activeBrewPath: activeBrew,
                fileManager: fileManager,
                executor: commandExecutor
            )

            let intelProfile = Self.scanPrefixProfile(
                prefixPath: "/usr/local",
                prefixName: "Intel (x86_64 Rosetta)",
                targetArch: .intel,
                hostArch: hostArch,
                activeBrewPath: activeBrew,
                fileManager: fileManager,
                executor: commandExecutor
            )

            let translated = Self.inspectRunningServices(
                services: services,
                hostArch: hostArch,
                fileManager: fileManager
            )

            return Self.buildComparison(
                hostArch: hostArch,
                rosetta: rosetta,
                activePrefix: activePath,
                arm64Profile: armProfile,
                intelProfile: intelProfile,
                translatedDaemons: translated
            )
        }.value

        self.comparison = comp
    }

    // MARK: - Low-Level Detection Heuristics

    nonisolated static func detectHostArchitecture() -> HostHardwareArchitecture {
        var sysInfo = utsname()
        guard uname(&sysInfo) == 0 else { return .unknown }
        let machine = withUnsafePointer(to: &sysInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        if machine.contains("arm64") || machine.contains("aarch64") {
            return .arm64
        } else if machine.contains("x86_64") {
            return .x86_64
        }
        return .unknown
    }

    nonisolated static func detectRosettaStatus(
        hostArch: HostHardwareArchitecture,
        fileManager: FileManager,
        executor: BrewStoreCommandExecutor
    ) -> RosettaStatus {
        guard hostArch == .arm64 else {
            return RosettaStatus(isSupported: false, isInstalled: false, isRunningDaemon: false)
        }

        let rosettaLibPath = "/Library/Apple/usr/libexec/oah/liboah.dylib"
        let libExists = fileManager.fileExists(atPath: rosettaLibPath)

        let archTest = executor.run(
            executablePath: "/usr/bin/arch",
            arguments: ["-x86_64", "/usr/bin/true"],
            timeout: 5,
            category: .readOnly
        )
        let isFunctional = archTest.succeeded || libExists

        let pgrepResult = executor.run(
            executablePath: "/usr/bin/pgrep",
            arguments: ["oahd"],
            timeout: 5,
            category: .readOnly
        )
        let isDaemonRunning = pgrepResult.succeeded && !pgrepResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return RosettaStatus(
            isSupported: true,
            isInstalled: isFunctional,
            isRunningDaemon: isDaemonRunning
        )
    }

    nonisolated static func scanPrefixProfile(
        prefixPath: String,
        prefixName: String,
        targetArch: BinaryArchitectureType,
        hostArch: HostHardwareArchitecture,
        activeBrewPath: String?,
        fileManager: FileManager,
        executor: BrewStoreCommandExecutor
    ) -> PrefixArchitectureProfile? {
        let brewPath = "\(prefixPath)/bin/brew"
        let isAvailable = fileManager.isExecutableFile(atPath: brewPath)

        let prefixObj = HomebrewPrefix(
            id: prefixPath,
            name: prefixName,
            brewExecutablePath: brewPath,
            architecture: targetArch,
            isAvailable: isAvailable,
            isActive: activeBrewPath == brewPath
        )

        guard isAvailable else {
            return PrefixArchitectureProfile(
                prefix: prefixObj,
                homebrewVersion: nil,
                formulaCount: 0,
                caskCount: 0,
                diskUsageBytes: 0,
                packages: []
            )
        }

        var hbVersion: String?
        let verRes = executor.run(
            executablePath: brewPath,
            arguments: ["--version"],
            timeout: 5,
            category: .readOnly
        )
        if verRes.succeeded {
            hbVersion = verRes.standardOutput.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces)
        }

        let cellarPath = "\(prefixPath)/Cellar"
        var formulaItems: [CrossArchPackageItem] = []
        var cellarSize: Int64 = 0

        if let formulaDirs = try? fileManager.contentsOfDirectory(atPath: cellarPath) {
            for fDir in formulaDirs where !fDir.hasPrefix(".") {
                let formulaDirURL = URL(fileURLWithPath: cellarPath).appendingPathComponent(fDir)
                let versions = (try? fileManager.contentsOfDirectory(atPath: formulaDirURL.path))?.filter { !$0.hasPrefix(".") } ?? []
                let activeVersion = versions.sorted().last ?? "installed"

                let fSize = calculateDirectorySize(at: formulaDirURL, fileManager: fileManager)
                cellarSize += fSize

                let binPath = findFormulaBinary(id: fDir, prefix: prefixPath, fileManager: fileManager)
                let arch: BinaryArchitectureType = if let binPath {
                    BrewStoreSecurityInspector.inspectBinaryArchitecture(at: binPath)
                } else {
                    targetArch
                }
                let isNative = (hostArch == .arm64 && (arch == .appleSilicon || arch == .universal2)) ||
                               (hostArch == .x86_64 && (arch == .intel || arch == .universal2))

                formulaItems.append(CrossArchPackageItem(
                    packageID: fDir,
                    name: fDir,
                    kind: .formula,
                    installedVersion: activeVersion,
                    prefixPath: prefixPath,
                    architecture: arch,
                    isNativeToHost: isNative,
                    binaryPath: binPath
                ))
            }
        }

        let caskroomPath = "\(prefixPath)/Caskroom"
        var caskItems: [CrossArchPackageItem] = []
        var caskroomSize: Int64 = 0

        if let caskDirs = try? fileManager.contentsOfDirectory(atPath: caskroomPath) {
            for cDir in caskDirs where !cDir.hasPrefix(".") {
                let caskDirURL = URL(fileURLWithPath: caskroomPath).appendingPathComponent(cDir)
                let versions = (try? fileManager.contentsOfDirectory(atPath: caskDirURL.path))?.filter { !$0.hasPrefix(".") } ?? []
                let activeVersion = versions.sorted().last ?? "installed"

                let cSize = calculateDirectorySize(at: caskDirURL, fileManager: fileManager)
                caskroomSize += cSize

                let appCandidates = [
                    "/Applications/\(cDir).app",
                    fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(cDir).app").path
                ]
                var arch = targetArch
                var binPath: String?
                for app in appCandidates where fileManager.fileExists(atPath: app) {
                    binPath = app
                    arch = BrewStoreSecurityInspector.inspectAppBundleArchitecture(at: app)
                    break
                }
                let isNative = (hostArch == .arm64 && (arch == .appleSilicon || arch == .universal2)) ||
                               (hostArch == .x86_64 && (arch == .intel || arch == .universal2))

                caskItems.append(CrossArchPackageItem(
                    packageID: cDir,
                    name: cDir,
                    kind: .cask,
                    installedVersion: activeVersion,
                    prefixPath: prefixPath,
                    architecture: arch,
                    isNativeToHost: isNative,
                    binaryPath: binPath
                ))
            }
        }

        let allPackages = (formulaItems + caskItems).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return PrefixArchitectureProfile(
            prefix: prefixObj,
            homebrewVersion: hbVersion,
            formulaCount: formulaItems.count,
            caskCount: caskItems.count,
            diskUsageBytes: cellarSize + caskroomSize,
            packages: allPackages
        )
    }

    private nonisolated static func calculateDirectorySize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = resourceValues.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private nonisolated static func findFormulaBinary(id: String, prefix: String, fileManager: FileManager) -> String? {
        let candidates = [
            "\(prefix)/bin/\(id)",
            "\(prefix)/opt/\(id)/bin/\(id)"
        ]
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        let optBin = "\(prefix)/opt/\(id)/bin"
        if let contents = try? fileManager.contentsOfDirectory(atPath: optBin) {
            for item in contents where !item.hasPrefix(".") {
                let p = "\(optBin)/\(item)"
                if fileManager.isExecutableFile(atPath: p) {
                    return p
                }
            }
        }
        return nil
    }

    nonisolated static func buildComparison(
        hostArch: HostHardwareArchitecture,
        rosetta: RosettaStatus,
        activePrefix: String?,
        arm64Profile: PrefixArchitectureProfile?,
        intelProfile: PrefixArchitectureProfile?,
        translatedDaemons: [TranslatedDaemonItem]
    ) -> DualArchitectureComparison {
        let armPackages = arm64Profile?.packages ?? []
        let intelPackages = intelProfile?.packages ?? []

        let armMap = Dictionary(grouping: armPackages, by: \.packageID).compactMapValues(\.first)
        let intelMap = Dictionary(grouping: intelPackages, by: \.packageID).compactMapValues(\.first)

        var dualInstalled: [DualPackageComparison] = []
        var armOnly: [CrossArchPackageItem] = []
        var intelOnly: [CrossArchPackageItem] = []

        let allIDs = Set(armMap.keys).union(intelMap.keys)

        for id in allIDs.sorted() {
            if let armItem = armMap[id], let intelItem = intelMap[id] {
                dualInstalled.append(DualPackageComparison(
                    packageID: id,
                    name: armItem.name,
                    kind: armItem.kind,
                    arm64Version: armItem.installedVersion,
                    intelVersion: intelItem.installedVersion,
                    arm64Path: armItem.prefixPath,
                    intelPath: intelItem.prefixPath,
                    isIdenticalVersion: armItem.installedVersion == intelItem.installedVersion
                ))
            } else if let armItem = armMap[id] {
                armOnly.append(armItem)
            } else if let intelItem = intelMap[id] {
                intelOnly.append(intelItem)
            }
        }

        return DualArchitectureComparison(
            hostArchitecture: hostArch,
            rosettaStatus: rosetta,
            activePrefixPath: activePrefix,
            arm64Profile: arm64Profile,
            intelProfile: intelProfile,
            dualInstalledPackages: dualInstalled,
            arm64OnlyPackages: armOnly,
            intelOnlyPackages: intelOnly,
            translatedDaemons: translatedDaemons
        )
    }

    nonisolated static func inspectRunningServices(
        services: [BrewStoreService],
        hostArch: HostHardwareArchitecture,
        fileManager: FileManager
    ) -> [TranslatedDaemonItem] {
        guard hostArch == .arm64 else { return [] }

        var results: [TranslatedDaemonItem] = []
        for svc in services where svc.isRunning {
            let bin = BrewStoreSecurityInspector.findFormulaBinaryPath(id: svc.name, name: svc.name)
            if let bin {
                let arch = BrewStoreSecurityInspector.inspectBinaryArchitecture(at: bin)
                let isTranslated = arch == .intel
                results.append(TranslatedDaemonItem(
                    serviceName: svc.name,
                    pid: 0,
                    isTranslated: isTranslated,
                    architecture: arch,
                    executablePath: bin
                ))
            }
        }
        return results
    }

    // MARK: - Actions & Cross-Architecture Operations

    func switchActivePrefix(to prefixPath: String, manager: HomebrewManager) {
        let brewPath = "\(prefixPath)/bin/brew"
        guard fileManager.isExecutableFile(atPath: brewPath) else { return }

        let arch: BinaryArchitectureType = prefixPath.contains("opt") ? .appleSilicon : .intel
        let prefix = HomebrewPrefix(
            id: prefixPath,
            name: prefixPath.contains("opt") ? "Apple Silicon (ARM64)" : "Intel (x86_64 Rosetta)",
            brewExecutablePath: brewPath,
            architecture: arch,
            isAvailable: true,
            isActive: true
        )
        BrewStorePrefixManager.shared.switchPrefix(to: prefix, manager: manager)
        Task {
            await scanDualArchitectureEnvironment(activeManager: manager)
        }
    }

    func crossInstallPackage(
        packageID: String,
        kind: BrewPackageKind,
        targetPrefix: String,
        manager: HomebrewManager
    ) async throws {
        isPerformingOperation = true
        operationStatus = "Installing '\(packageID)' into \(targetPrefix)…"
        defer {
            isPerformingOperation = false
            operationStatus = nil
        }

        let targetBrew = "\(targetPrefix)/bin/brew"
        guard fileManager.isExecutableFile(atPath: targetBrew) else {
            throw NSError(domain: "BrewStoreDualArch", code: 404, userInfo: [NSLocalizedDescriptionKey: "Homebrew executable not found at \(targetBrew)"])
        }

        var args: [String] = []
        let execPath: String
        if targetPrefix == "/usr/local" {
            execPath = "/usr/bin/arch"
            args = ["-x86_64", targetBrew, "install"]
        } else {
            execPath = "/usr/bin/arch"
            args = ["-arm64", targetBrew, "install"]
        }

        if kind == .cask {
            args.append("--cask")
        }
        args.append(packageID)

        let result = commandExecutor.run(
            executablePath: execPath,
            arguments: args,
            timeout: 180,
            category: .reversibleMutation
        )

        guard result.succeeded else {
            throw NSError(domain: "BrewStoreDualArch", code: Int(result.terminationStatus ?? -1), userInfo: [NSLocalizedDescriptionKey: result.standardError.isEmpty ? "Cross-architecture install failed." : result.standardError])
        }

        await scanDualArchitectureEnvironment(activeManager: manager)
    }

    func uninstallFromPrefix(
        packageID: String,
        kind: BrewPackageKind,
        prefixPath: String,
        manager: HomebrewManager
    ) async throws {
        isPerformingOperation = true
        operationStatus = "Uninstalling '\(packageID)' from \(prefixPath)…"
        defer {
            isPerformingOperation = false
            operationStatus = nil
        }

        let targetBrew = "\(prefixPath)/bin/brew"
        guard fileManager.isExecutableFile(atPath: targetBrew) else {
            throw NSError(domain: "BrewStoreDualArch", code: 404, userInfo: [NSLocalizedDescriptionKey: "Homebrew executable not found at \(targetBrew)"])
        }

        var args = ["uninstall"]
        if kind == .cask {
            args.append("--cask")
        }
        args.append(packageID)

        let result = commandExecutor.run(
            executablePath: targetBrew,
            arguments: args,
            timeout: 60,
            category: .destructiveMutation
        )

        guard result.succeeded else {
            throw NSError(domain: "BrewStoreDualArch", code: Int(result.terminationStatus ?? -1), userInfo: [NSLocalizedDescriptionKey: result.standardError.isEmpty ? "Uninstall failed." : result.standardError])
        }

        await scanDualArchitectureEnvironment(activeManager: manager)
    }

    static var rosettaInstallCommand: String {
        "/usr/sbin/softwareupdate --install-rosetta --agree-to-license"
    }

    static var intelBrewBootstrapCommand: String {
        "arch -x86_64 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    }
}
