import AppKit
import Combine
import Foundation
import SwiftUI

enum BundleCheckStatus: String, Codable, CaseIterable, Equatable {
    case satisfied = "Satisfied"
    case drifted = "Drift Detected"
    case missingBrewfile = "No Brewfile Found"
    case checking = "Checking Drift…"

    var badgeColor: Color {
        switch self {
        case .satisfied: .green
        case .drifted: .orange
        case .missingBrewfile: .secondary
        case .checking: .blue
        }
    }

    var iconName: String {
        switch self {
        case .satisfied: "checkmark.seal.fill"
        case .drifted: "arrow.triangle.pull"
        case .missingBrewfile: "doc.questionmark"
        case .checking: "arrow.clockwise"
        }
    }
}

enum DeclarativeEntryKind: String, Codable, CaseIterable {
    case tap = "Tap"
    case brew = "Formula"
    case cask = "Cask"
    case mas = "Mac App Store"
    case vscode = "VS Code Extension"

    var systemImage: String {
        switch self {
        case .tap: "point.3.connected.trianglepath.dotted"
        case .brew: "terminal.fill"
        case .cask: "app.fill"
        case .mas: "cart.fill"
        case .vscode: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct DeclarativeBrewfileEntry: Identifiable, Hashable, Codable {
    var id: String {
        "\(kind.rawValue):\(name)"
    }

    let name: String
    let kind: DeclarativeEntryKind
    var options: [String: String]
    var comment: String?
    var isInstalled: Bool

    init(
        name: String,
        kind: DeclarativeEntryKind,
        options: [String: String] = [:],
        comment: String? = nil,
        isInstalled: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.options = options
        self.comment = comment
        self.isInstalled = isInstalled
    }
}

struct BrewfileDriftReport: Identifiable, Hashable, Codable {
    var id: String {
        fileURL.path
    }

    let fileURL: URL
    let status: BundleCheckStatus
    let lastChecked: Date
    let missingFormulae: [String]
    let missingCasks: [String]
    let missingTaps: [String]
    let missingMasApps: [BrewStoreBrewfileMASEntry]
    let missingVSCodeExtensions: [String]
    let unmanagedFormulae: [String]
    let unmanagedCasks: [String]
    let unmanagedTaps: [String]

    var totalMissingCount: Int {
        missingFormulae.count + missingCasks.count + missingTaps.count + missingMasApps.count + missingVSCodeExtensions.count
    }

    var totalUnmanagedCount: Int {
        unmanagedFormulae.count + unmanagedCasks.count + unmanagedTaps.count
    }

    var isSatisfied: Bool {
        totalMissingCount == 0 && totalUnmanagedCount == 0
    }
}

@MainActor
final class BrewStoreBundleManager: ObservableObject {
    static let shared = BrewStoreBundleManager()

    private let userDefaultsKey = "BrewStoreTrackedBrewfileURL"

    @Published var trackedBrewfileURL: URL?
    @Published var activeDriftReport: BrewfileDriftReport?
    @Published var scannedProjectBrewfiles: [URL] = []
    @Published var isOperating: Bool = false
    @Published var isCheckingDrift: Bool = false
    @Published var activeOperationTitle: String? = nil
    @Published var errorMessage: String? = nil
    @Published var dryRunCleanupList: [String] = []

    private let commandExecutor: BrewStoreCommandExecutor

    init(commandExecutor: BrewStoreCommandExecutor = .shared) {
        self.commandExecutor = commandExecutor
        loadTrackedURL()
    }

    // MARK: - Tracked URL Management

    func setTrackedBrewfile(url: URL?) {
        trackedBrewfileURL = url
        if let url {
            UserDefaults.standard.set(url.path, forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }

    private func loadTrackedURL() {
        if let savedPath = UserDefaults.standard.string(forKey: userDefaultsKey),
           FileManager.default.fileExists(atPath: savedPath) {
            trackedBrewfileURL = URL(fileURLWithPath: savedPath)
            return
        }

        // Search standard locations: ~/.Brewfile, ~/.homebrew/Brewfile
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".Brewfile"),
            home.appendingPathComponent(".homebrew/Brewfile"),
            home.appendingPathComponent(".config/homebrew/Brewfile")
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                trackedBrewfileURL = candidate
                return
            }
        }
    }

    // MARK: - Live Drift Checking

    func checkDrift(
        for fileURL: URL,
        packages: [BrewStorePackage],
        taps: [BrewStoreTap]
    ) async -> BrewfileDriftReport {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let report = BrewfileDriftReport(
                fileURL: fileURL,
                status: .missingBrewfile,
                lastChecked: Date(),
                missingFormulae: [],
                missingCasks: [],
                missingTaps: [],
                missingMasApps: [],
                missingVSCodeExtensions: [],
                unmanagedFormulae: [],
                unmanagedCasks: [],
                unmanagedTaps: []
            )
            activeDriftReport = report
            return report
        }

        isCheckingDrift = true
        defer { isCheckingDrift = false }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            let report = BrewfileDriftReport(
                fileURL: fileURL,
                status: .missingBrewfile,
                lastChecked: Date(),
                missingFormulae: [],
                missingCasks: [],
                missingTaps: [],
                missingMasApps: [],
                missingVSCodeExtensions: [],
                unmanagedFormulae: [],
                unmanagedCasks: [],
                unmanagedTaps: []
            )
            activeDriftReport = report
            return report
        }

        let parsed = BrewStoreBrewfileParser.parse(content)
        let diff = BrewStoreBrewfileParser.diff(parsed, installedPackages: packages, installedTaps: taps)

        let status: BundleCheckStatus = (diff.missingFormulae.isEmpty && diff.missingCasks.isEmpty && diff.missingTaps.isEmpty)
            ? .satisfied
            : .drifted

        let report = BrewfileDriftReport(
            fileURL: fileURL,
            status: status,
            lastChecked: Date(),
            missingFormulae: diff.missingFormulae,
            missingCasks: diff.missingCasks,
            missingTaps: diff.missingTaps,
            missingMasApps: parsed.masApps,
            missingVSCodeExtensions: [],
            unmanagedFormulae: diff.extraInstalledFormulae,
            unmanagedCasks: diff.extraInstalledCasks,
            unmanagedTaps: []
        )

        activeDriftReport = report
        return report
    }

    // MARK: - Project / Repository Brewfile Scanner

    func scanDirectory(at rootURL: URL) async -> [URL] {
        let resolvedRoot = rootURL.resolvingSymlinksInPath()
        var results: [URL] = []
        let fm = FileManager.default

        // Direct candidate checks
        let directCandidates = [
            resolvedRoot.appendingPathComponent("Brewfile"),
            resolvedRoot.appendingPathComponent(".Brewfile"),
            resolvedRoot.appendingPathComponent("Brewfile.local")
        ]

        for candidate in directCandidates {
            if fm.fileExists(atPath: candidate.path) {
                results.append(candidate)
            }
        }

        // Subdirectory scan up to 2 levels deep
        if let enumerator = fm.enumerator(
            at: resolvedRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                if enumerator.level > 2 {
                    enumerator.skipDescendants()
                    continue
                }
                let resolved = fileURL.resolvingSymlinksInPath()
                let filename = resolved.lastPathComponent
                if filename == "Brewfile" || filename == "Brewfile.local" {
                    if !results.contains(resolved) {
                        results.append(resolved)
                    }
                }
            }
        }

        scannedProjectBrewfiles = results
        return results
    }

    // MARK: - Declarative Bundle Actions

    func dumpSystemBrewfile(
        to fileURL: URL,
        includeComments: Bool = true,
        manager: HomebrewManager? = nil
    ) async -> (success: Bool, message: String) {
        guard !isOperating else { return (false, "Another operation is currently in progress.") }
        isOperating = true
        activeOperationTitle = "Dumping Brewfile"
        defer {
            isOperating = false
            activeOperationTitle = nil
        }

        let brewPath = manager?.brewPath ?? resolveBrewBinary()
        let result = commandExecutor.run(
            executablePath: brewPath,
            arguments: ["bundle", "dump", "--file=\(fileURL.path)", "--force"],
            timeout: 60,
            category: .reversibleMutation
        )

        if result.succeeded {
            setTrackedBrewfile(url: fileURL)
            return (true, "Exported system state to \(fileURL.lastPathComponent).")
        } else {
            // Fallback: programmatically generate Brewfile if CLI dump fails
            if let packages = manager?.packages, let taps = manager?.taps {
                let content = BrewStoreBrewfileParser.generate(packages: packages, taps: taps)
                if (try? content.write(to: fileURL, atomically: true, encoding: .utf8)) != nil {
                    setTrackedBrewfile(url: fileURL)
                    return (true, "Exported system state via native bundler to \(fileURL.lastPathComponent).")
                }
            }
            let err = result.standardError.isEmpty ? result.standardOutput : result.standardError
            return (false, "Failed to dump Brewfile: \(err)")
        }
    }

    func installBundle(
        from fileURL: URL,
        noLock: Bool = true,
        manager: HomebrewManager? = nil
    ) async -> (success: Bool, message: String) {
        guard !isOperating else { return (false, "Another operation is currently in progress.") }
        isOperating = true
        activeOperationTitle = "Installing Brewfile Bundle"
        defer {
            isOperating = false
            activeOperationTitle = nil
        }

        let brewPath = manager?.brewPath ?? resolveBrewBinary()
        var args = ["bundle", "install", "--file=\(fileURL.path)"]
        if noLock {
            args.append("--no-lock")
        }

        let result = commandExecutor.run(
            executablePath: brewPath,
            arguments: args,
            timeout: 600,
            category: .reversibleMutation
        )

        if result.succeeded {
            manager?.refresh()
            return (true, "Successfully synchronized dependencies from \(fileURL.lastPathComponent).")
        } else {
            let err = result.standardError.isEmpty ? result.standardOutput : result.standardError
            return (false, "Bundle install failed: \(err)")
        }
    }

    func dryRunCleanup(for fileURL: URL) async -> (items: [String], message: String) {
        let brewPath = resolveBrewBinary()
        let result = commandExecutor.run(
            executablePath: brewPath,
            arguments: ["bundle", "cleanup", "--file=\(fileURL.path)"],
            timeout: 60,
            category: .readOnly
        )

        let parsed = Self.parseCleanupItems(from: result.standardOutput)
        dryRunCleanupList = parsed
        return (parsed, "Found \(parsed.count) unmanaged package\(parsed.count == 1 ? "" : "s") not in Brewfile.")
    }

    func executeCleanup(
        for fileURL: URL,
        zap: Bool = false,
        manager: HomebrewManager? = nil
    ) async -> (success: Bool, message: String) {
        guard !isOperating else { return (false, "Another operation is currently in progress.") }
        isOperating = true
        activeOperationTitle = "Cleaning up Unmanaged Packages"
        defer {
            isOperating = false
            activeOperationTitle = nil
        }

        let brewPath = manager?.brewPath ?? resolveBrewBinary()
        var args = ["bundle", "cleanup", "--file=\(fileURL.path)", "--force"]
        if zap {
            args.append("--zap")
        }

        let result = commandExecutor.run(
            executablePath: brewPath,
            arguments: args,
            timeout: 300,
            category: .destructiveMutation
        )

        if result.succeeded {
            dryRunCleanupList = []
            manager?.refresh()
            return (true, "Cleaned up unmanaged packages.")
        } else {
            let err = result.standardError.isEmpty ? result.standardOutput : result.standardError
            return (false, "Cleanup failed: \(err)")
        }
    }

    // MARK: - Internal Helpers

    private func resolveBrewBinary() -> String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        return "/usr/local/bin/brew"
    }

    nonisolated static func parseCleanupItems(from output: String) -> [String] {
        var items: [String] = []
        var capturing = false

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Would uninstall") {
                capturing = true
                continue
            }
            if capturing {
                if trimmed.isEmpty || trimmed.hasPrefix("==>") {
                    capturing = false
                } else {
                    items.append(trimmed)
                }
            }
        }
        return items
    }
}
