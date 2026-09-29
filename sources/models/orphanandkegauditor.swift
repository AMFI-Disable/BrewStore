import AppKit
import Foundation

// MARK: - Leaf & Keg Models

enum LeafPackageCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case orphan = "Orphan Dependencies"
    case explicit = "Requested Leaves"
    case dependency = "Active Dependencies"

    var id: String { rawValue }
}

struct LeafPackageItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let version: String
    let category: LeafPackageCategory
    let sizeBytes: Int64
    let formattedSize: String
    let dependencies: [String]
    let dependents: [String]
    let cellarPath: String
}

struct KegOnlyPackageItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let version: String
    let isForceLinked: Bool
    let linkedKeg: String?
    let reasonCode: String
    let explanation: String
    let prefixPath: String
    let binExists: Bool
    let libExists: Bool
    let includeExists: Bool

    var pathExportSnippet: String {
        "export PATH=\"\(prefixPath)/bin:$PATH\""
    }

    var compilerLdFlagsSnippet: String {
        "export LDFLAGS=\"-L\(prefixPath)/lib\""
    }

    var compilerCppFlagsSnippet: String {
        "export CPPFLAGS=\"-I\(prefixPath)/include\""
    }

    var pkgConfigSnippet: String {
        "export PKG_CONFIG_PATH=\"\(prefixPath)/lib/pkgconfig\""
    }

    var fullShellSnippet: String {
        var lines: [String] = []
        if binExists {
            lines.append("export PATH=\"\(prefixPath)/bin:$PATH\"")
        }
        if libExists {
            lines.append("export LDFLAGS=\"-L\(prefixPath)/lib\"")
        }
        if includeExists {
            lines.append("export CPPFLAGS=\"-I\(prefixPath)/include\"")
        }
        if libExists {
            lines.append("export PKG_CONFIG_PATH=\"\(prefixPath)/lib/pkgconfig\"")
        }
        return lines.joined(separator: "\n")
    }

    var humanReadableReason: String {
        if !explanation.isEmpty {
            return explanation
        }
        switch reasonCode.lowercased() {
        case ":provided_by_macos", "provided_by_macos":
            return "macOS already provides this software; installing another version globally can cause conflicts."
        case ":versioned_formula", "versioned_formula":
            return "This is an alternate versioned formula. Homebrew isolates versioned packages to prevent shadowing standard commands."
        case ":shadowed_by_macos", "shadowed_by_macos":
            return "Shadows a core macOS command or library."
        case ":by_default", "by_default":
            return "Isolated by default to prevent unexpected system toolchain collisions."
        default:
            return "Isolated from global PATH by Homebrew formula configuration."
        }
    }
}

struct OrphanAndKegAuditReport: Hashable, Sendable {
    let orphans: [LeafPackageItem]
    let explicitLeaves: [LeafPackageItem]
    let kegOnlyPackages: [KegOnlyPackageItem]
    let totalOrphanBytes: Int64
    let formattedTotalOrphanSpace: String
    let scannedAt: Date
}

// MARK: - Auditor Engine

@MainActor
final class OrphanAndKegAuditor: ObservableObject {
    static let shared = OrphanAndKegAuditor()

    @Published private(set) var report: OrphanAndKegAuditReport?
    @Published private(set) var isAuditing: Bool = false
    @Published private(set) var operatingPackageID: String?
    @Published var auditError: String?

    private let commandExecutor: BrewStoreCommandExecutor

    init(commandExecutor: BrewStoreCommandExecutor = .shared) {
        self.commandExecutor = commandExecutor
    }

    // MARK: - Audit Scan

    func auditEnvironment(prefix: String, manager: HomebrewManager? = nil) {
        guard !isAuditing else { return }
        isAuditing = true
        auditError = nil

        let executor = commandExecutor
        let brewPath = manager?.brewPath ?? ((prefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("brew")

        Task.detached(priority: .userInitiated) {
            let result = Self.performAuditScan(
                prefix: prefix,
                brewPath: brewPath,
                executor: executor
            )

            await MainActor.run {
                self.report = result
                self.isAuditing = false
            }
        }
    }

    nonisolated static func performAuditScan(
        prefix: String,
        brewPath: String,
        executor: BrewStoreCommandExecutor
    ) -> OrphanAndKegAuditReport {
        let fm = FileManager.default
        let cellarURL = URL(fileURLWithPath: prefix).appendingPathComponent("Cellar")
        let optURL = URL(fileURLWithPath: prefix).appendingPathComponent("opt")

        // 1. Fetch orphan leaves: brew leaves -p
        let orphanResult = executor.run(
            executablePath: brewPath,
            arguments: ["leaves", "-p"],
            timeout: 15,
            category: .readOnly
        )
        let orphanIDs = Set(
            orphanResult.standardOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        // 2. Fetch requested leaves: brew leaves -r
        let requestedResult = executor.run(
            executablePath: brewPath,
            arguments: ["leaves", "-r"],
            timeout: 15,
            category: .readOnly
        )
        let requestedIDs = Set(
            requestedResult.standardOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        // 3. Fetch installed metadata: brew info --json=v2 --installed
        let infoResult = executor.run(
            executablePath: brewPath,
            arguments: ["info", "--json=v2", "--installed"],
            timeout: 25,
            category: .readOnly
        )

        var kegOnlyMap: [String: (reason: String, explanation: String, linkedKeg: String?)] = [:]
        var formulaMetadataMap: [String: (version: String, deps: [String], size: Int64)] = [:]

        if let data = infoResult.standardOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let formulae = json["formulae"] as? [[String: Any]] {
            for formula in formulae {
                guard let name = formula["name"] as? String else { continue }
                let fullName = (formula["full_name"] as? String) ?? name
                let linkedKeg = formula["linked_keg"] as? String
                let isKegOnly = (formula["keg_only"] as? Bool) ?? false

                if isKegOnly {
                    var reasonCode = ""
                    var explanation = ""
                    if let reasonDict = formula["keg_only_reason"] as? [String: Any] {
                        reasonCode = (reasonDict["reason"] as? String) ?? ""
                        explanation = (reasonDict["explanation"] as? String) ?? ""
                    }
                    kegOnlyMap[name.lowercased()] = (reasonCode, explanation, linkedKeg)
                    kegOnlyMap[fullName.lowercased()] = (reasonCode, explanation, linkedKeg)
                }

                // Extract installed version and dependencies
                var installedVersion = ""
                if let installedList = formula["installed"] as? [[String: Any]],
                   let firstInstalled = installedList.first {
                    installedVersion = (firstInstalled["version"] as? String) ?? ""
                }
                var deps: [String] = []
                if let depList = formula["dependencies"] as? [String] {
                    deps = depList
                }

                formulaMetadataMap[name.lowercased()] = (installedVersion, deps, 0)
            }
        }

        // 4. File-system scanning of Cellar packages
        var orphans: [LeafPackageItem] = []
        var explicitLeaves: [LeafPackageItem] = []
        var totalOrphanBytes: Int64 = 0

        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useMB, .useGB, .useKB]
        byteFormatter.countStyle = .file

        if let cellarContents = try? fm.contentsOfDirectory(at: cellarURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for dir in cellarContents {
                let pkgID = dir.lastPathComponent
                let lowerID = pkgID.lowercased()
                let pkgCellarPath = dir.path

                // Calculate package size in Cellar
                let sizeBytes = BrewStoreDiskStorageAnalyzerManager.computeDirectorySize(url: dir)
                let formattedSize = byteFormatter.string(fromByteCount: sizeBytes)

                // Get latest installed version from directory or metadata
                var version = formulaMetadataMap[lowerID]?.version ?? ""
                if version.isEmpty {
                    if let versions = try? fm.contentsOfDirectory(atPath: pkgCellarPath) {
                        let filtered = versions.filter { !$0.hasPrefix(".") && $0 != "INSTALL_RECEIPT.json" && $0 != ".brew" }
                        version = filtered.sorted().last ?? "installed"
                    } else {
                        version = "installed"
                    }
                }

                // If receipt exists, we can extract runtime dependencies
                var deps = formulaMetadataMap[lowerID]?.deps ?? []
                let receiptPath = ((pkgCellarPath as NSString).appendingPathComponent(version) as NSString).appendingPathComponent("INSTALL_RECEIPT.json")
                if deps.isEmpty, let receiptData = try? Data(contentsOf: URL(fileURLWithPath: receiptPath)),
                   let receiptJson = try? JSONSerialization.jsonObject(with: receiptData) as? [String: Any],
                   let runtimeDeps = receiptJson["runtime_dependencies"] as? [[String: Any]] {
                    deps = runtimeDeps.compactMap { ($0["full_name"] as? String) ?? ($0["name"] as? String) }
                }

                // Check fallback for keg_only in .brew/<pkgID>.rb if not discovered in json
                if kegOnlyMap[lowerID] == nil {
                    let rbPath = ((pkgCellarPath as NSString).appendingPathComponent(version) as NSString)
                        .appendingPathComponent(".brew/\(pkgID).rb")
                    if let rbContent = try? String(contentsOfFile: rbPath, encoding: .utf8),
                       rbContent.contains("keg_only") {
                        var reason = ":by_default"
                        if rbContent.contains(":provided_by_macos") {
                            reason = ":provided_by_macos"
                        } else if rbContent.contains(":versioned_formula") {
                            reason = ":versioned_formula"
                        } else if rbContent.contains(":shadowed_by_macos") {
                            reason = ":shadowed_by_macos"
                        }
                        kegOnlyMap[lowerID] = (reason, "", nil)
                    }
                }

                // Categorize
                if orphanIDs.contains(pkgID) {
                    totalOrphanBytes += sizeBytes
                    orphans.append(LeafPackageItem(
                        id: pkgID,
                        name: pkgID,
                        version: version,
                        category: .orphan,
                        sizeBytes: sizeBytes,
                        formattedSize: formattedSize,
                        dependencies: deps,
                        dependents: [],
                        cellarPath: pkgCellarPath
                    ))
                } else if requestedIDs.contains(pkgID) {
                    explicitLeaves.append(LeafPackageItem(
                        id: pkgID,
                        name: pkgID,
                        version: version,
                        category: .explicit,
                        sizeBytes: sizeBytes,
                        formattedSize: formattedSize,
                        dependencies: deps,
                        dependents: [],
                        cellarPath: pkgCellarPath
                    ))
                }
            }
        }

        // Sort orphans by size descending (largest reclaimable first)
        orphans.sort { $0.sizeBytes > $1.sizeBytes }
        explicitLeaves.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // 5. Build Keg-Only Package Items
        var kegOnlyPackages: [KegOnlyPackageItem] = []
        for (pkgID, info) in kegOnlyMap {
            let optPackageURL = optURL.appendingPathComponent(pkgID)
            let prefixPath = optPackageURL.path

            // Check what folders exist in opt/<pkgID>
            let binExists = fm.fileExists(atPath: (prefixPath as NSString).appendingPathComponent("bin"))
            let libExists = fm.fileExists(atPath: (prefixPath as NSString).appendingPathComponent("lib"))
            let includeExists = fm.fileExists(atPath: (prefixPath as NSString).appendingPathComponent("include"))

            // Check whether it is force linked:
            // Either info.linkedKeg is non-nil or bin/package exists in <prefix>/bin as a link
            var isForceLinked = (info.linkedKeg?.isEmpty == false)
            if !isForceLinked, binExists {
                let binDir = (prefix as NSString).appendingPathComponent("bin")
                let defaultBinPath = (binDir as NSString).appendingPathComponent(pkgID)
                if let dest = try? fm.destinationOfSymbolicLink(atPath: defaultBinPath),
                   dest.contains(pkgID) {
                    isForceLinked = true
                }
            }

            let version = formulaMetadataMap[pkgID]?.version ?? info.linkedKeg ?? "keg-only"

            // De-duplicate by primary name
            if !kegOnlyPackages.contains(where: { $0.id.lowercased() == pkgID }) {
                kegOnlyPackages.append(KegOnlyPackageItem(
                    id: pkgID,
                    name: pkgID,
                    version: version,
                    isForceLinked: isForceLinked,
                    linkedKeg: info.linkedKeg,
                    reasonCode: info.reason,
                    explanation: info.explanation,
                    prefixPath: prefixPath,
                    binExists: binExists,
                    libExists: libExists,
                    includeExists: includeExists
                ))
            }
        }

        kegOnlyPackages.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return OrphanAndKegAuditReport(
            orphans: orphans,
            explicitLeaves: explicitLeaves,
            kegOnlyPackages: kegOnlyPackages,
            totalOrphanBytes: totalOrphanBytes,
            formattedTotalOrphanSpace: byteFormatter.string(fromByteCount: totalOrphanBytes),
            scannedAt: Date()
        )
    }

    // MARK: - Actions

    func pruneSingleOrphan(packageID: String, prefix: String, manager: HomebrewManager? = nil) async -> Bool {
        guard operatingPackageID == nil else { return false }
        operatingPackageID = packageID
        defer { operatingPackageID = nil }

        let brewPath = manager?.brewPath ?? ((prefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("brew")
        let result = commandExecutor.run(
            executablePath: brewPath,
            arguments: ["uninstall", packageID],
            timeout: 60,
            category: .destructiveMutation
        )

        if result.succeeded {
            auditEnvironment(prefix: prefix, manager: manager)
            manager?.refresh()
            return true
        } else {
            let msg = BrewStoreHumanizedErrorResolver.humanizedMessage(from: result.standardError, fallback: "Failed to prune \(packageID).")
            auditError = msg
            return false
        }
    }

    func pruneAllOrphans(prefix: String, manager: HomebrewManager? = nil) async -> (success: Bool, message: String) {
        guard operatingPackageID == nil else { return (false, "Another operation is in progress.") }
        operatingPackageID = "autoremove"
        defer { operatingPackageID = nil }

        let brewPath = manager?.brewPath ?? ((prefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("brew")

        let result = commandExecutor.run(
            executablePath: brewPath,
            arguments: ["autoremove"],
            timeout: 120,
            category: .destructiveMutation
        )

        if result.succeeded {
            auditEnvironment(prefix: prefix, manager: manager)
            manager?.refresh()
            return (true, "Cleaned up all unneeded orphan dependencies.")
        } else {
            let msg = BrewStoreHumanizedErrorResolver.humanizedMessage(from: result.standardError, fallback: "Orphan cleanup did not complete.")
            auditError = msg
            return (false, msg)
        }
    }

    func toggleKegLink(packageID: String, forceLink: Bool, prefix: String, manager: HomebrewManager? = nil) async -> (success: Bool, message: String) {
        guard operatingPackageID == nil else { return (false, "Another operation is in progress.") }
        operatingPackageID = packageID
        defer { operatingPackageID = nil }

        let brewPath = manager?.brewPath ?? ((prefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("brew")
        let args: [String]
        if forceLink {
            args = ["link", "--overwrite", "--force", packageID]
        } else {
            args = ["unlink", packageID]
        }

        let result = commandExecutor.run(
            executablePath: brewPath,
            arguments: args,
            timeout: 45,
            category: .reversibleMutation
        )

        if result.succeeded {
            auditEnvironment(prefix: prefix, manager: manager)
            manager?.refresh()
            let actionName = forceLink ? "Force-linked" : "Unlinked"
            return (true, "\(actionName) \(packageID) successfully.")
        } else {
            let msg = BrewStoreHumanizedErrorResolver.humanizedMessage(from: result.standardError, fallback: "Operation failed on \(packageID).")
            auditError = msg
            return (false, msg)
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
