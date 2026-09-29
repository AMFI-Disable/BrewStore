import AppKit
import CryptoKit
import Foundation

// MARK: - Bottle Integrity Status

enum BottleIntegrityStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case verifiedBottle = "Official Verified Bottle"
    case builtFromSource = "Built From Source (--build-from-source)"
    case unmanagedOrManual = "Unmanaged / Missing Receipt"
    case corruptedOrTampered = "Corrupted / Missing Binaries"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .verifiedBottle: "checkmark.shield.fill"
        case .builtFromSource: "hammer.fill"
        case .unmanagedOrManual: "questionmark.circle.fill"
        case .corruptedOrTampered: "exclamationmark.shield.fill"
        }
    }

    var isHealthy: Bool {
        self == .verifiedBottle || self == .builtFromSource
    }
}

// MARK: - Binary Checksum Item

struct BinaryChecksumItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let relativePath: String
    let fullPath: String
    let sizeBytes: Int64
    let formattedSize: String
    let sha256: String
    let isMachO: Bool
    let exists: Bool
}

// MARK: - Bottle Integrity Report

struct BottleIntegrityReport: Hashable, Codable, Sendable {
    let packageID: String
    let packageName: String
    let version: String
    let status: BottleIntegrityStatus
    let bottleSHA256: String?
    let bottleArch: String?
    let compiler: String?
    let sourceModified: Bool
    let pouredFromBottle: Bool
    let installedFilesCount: Int
    let binaryChecksums: [BinaryChecksumItem]
    let missingFiles: [String]
    let failureReason: String?

    var hasIntegrityIssue: Bool {
        !status.isHealthy || !missingFiles.isEmpty
    }

    // Backward-compatible initializer for existing callers and tests
    init(
        packageID: String,
        packageName: String? = nil,
        version: String = "installed",
        status: BottleIntegrityStatus,
        bottleSHA256: String?,
        bottleArch: String?,
        compiler: String?,
        sourceModified: Bool,
        pouredFromBottle: Bool = true,
        installedFilesCount: Int = 0,
        binaryChecksums: [BinaryChecksumItem] = [],
        missingFiles: [String] = [],
        failureReason: String? = nil
    ) {
        self.packageID = packageID
        self.packageName = packageName ?? packageID
        self.version = version
        self.status = status
        self.bottleSHA256 = bottleSHA256
        self.bottleArch = bottleArch
        self.compiler = compiler
        self.sourceModified = sourceModified
        self.pouredFromBottle = pouredFromBottle
        self.installedFilesCount = installedFilesCount
        self.binaryChecksums = binaryChecksums
        self.missingFiles = missingFiles
        self.failureReason = failureReason
    }
}

// MARK: - System Bottle Audit Summary

struct SystemBottleAuditSummary: Hashable, Sendable {
    let reports: [BottleIntegrityReport]
    let verifiedCount: Int
    let builtFromSourceCount: Int
    let corruptedCount: Int
    let unmanagedCount: Int
    let scannedAt: Date

    var totalIssuesCount: Int {
        corruptedCount + unmanagedCount
    }
}

// MARK: - Auditor Engine

@MainActor
final class BrewStoreBottleIntegrityAuditor: ObservableObject {
    static let shared = BrewStoreBottleIntegrityAuditor()

    @Published private(set) var summary: SystemBottleAuditSummary?
    @Published private(set) var isAuditing: Bool = false
    @Published private(set) var operatingPackageID: String?
    @Published var auditError: String?

    private let commandExecutor: BrewStoreCommandExecutor

    init(commandExecutor: BrewStoreCommandExecutor = .shared) {
        self.commandExecutor = commandExecutor
    }

    // MARK: - Cryptographic Hashing

    nonisolated static func computeFileSHA256(at url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = fileHandle.readData(ofLength: 65536)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Single Package Audit

    nonisolated static func auditPackage(package: BrewStorePackage, prefix: String) -> BottleIntegrityReport {
        guard package.kind == .formula, package.isInstalled else {
            return BottleIntegrityReport(
                packageID: package.id,
                packageName: package.name,
                version: package.version,
                status: .verifiedBottle,
                bottleSHA256: nil,
                bottleArch: "universal",
                compiler: "clang",
                sourceModified: false
            )
        }

        let cellarURL = URL(fileURLWithPath: prefix).appendingPathComponent("Cellar").appendingPathComponent(package.name)
        let fm = FileManager.default

        guard let versions = try? fm.contentsOfDirectory(at: cellarURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
              !versions.isEmpty else {
            return BottleIntegrityReport(
                packageID: package.id,
                packageName: package.name,
                version: package.installedVersion ?? package.version,
                status: .unmanagedOrManual,
                bottleSHA256: nil,
                bottleArch: nil,
                compiler: nil,
                sourceModified: false,
                pouredFromBottle: false,
                failureReason: "Cellar directory not found"
            )
        }

        // Pick latest version folder
        let sortedVersions = versions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let versionDir = sortedVersions.last else {
            return BottleIntegrityReport(
                packageID: package.id,
                packageName: package.name,
                version: package.installedVersion ?? package.version,
                status: .unmanagedOrManual,
                bottleSHA256: nil,
                bottleArch: nil,
                compiler: nil,
                sourceModified: false
            )
        }

        let versionString = versionDir.lastPathComponent
        let receiptURL = versionDir.appendingPathComponent("INSTALL_RECEIPT.json")

        guard let receiptData = try? Data(contentsOf: receiptURL),
              let receiptJson = try? JSONSerialization.jsonObject(with: receiptData) as? [String: Any] else {
            return BottleIntegrityReport(
                packageID: package.id,
                packageName: package.name,
                version: versionString,
                status: .unmanagedOrManual,
                bottleSHA256: nil,
                bottleArch: nil,
                compiler: nil,
                sourceModified: false,
                pouredFromBottle: false,
                failureReason: "Missing or unreadable INSTALL_RECEIPT.json"
            )
        }

        // Parse base receipt
        var report = parseReceiptJSON(receiptJson, packageID: package.id, packageName: package.name, version: versionString)

        // Enrich with SBOM bottle hash if available
        let sbomURL = versionDir.appendingPathComponent("sbom.spdx.json")
        if let sbomData = try? Data(contentsOf: sbomURL),
           let sbomJson = try? JSONSerialization.jsonObject(with: sbomData) as? [String: Any],
           let packages = sbomJson["packages"] as? [[String: Any]] {
            for pkg in packages {
                if let downloadLoc = pkg["downloadLocation"] as? String,
                   downloadLoc.contains("sha256:") {
                    let parts = downloadLoc.components(separatedBy: "sha256:")
                    if parts.count > 1, let hash = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
                        report = BottleIntegrityReport(
                            packageID: report.packageID,
                            packageName: report.packageName,
                            version: report.version,
                            status: report.status,
                            bottleSHA256: hash,
                            bottleArch: report.bottleArch,
                            compiler: report.compiler,
                            sourceModified: report.sourceModified,
                            pouredFromBottle: report.pouredFromBottle
                        )
                        break
                    }
                }
            }
        }

        // Verify executables and linkage files
        let (checksums, missing, totalCount) = inspectCellarFiles(versionDir: versionDir, receiptJson: receiptJson)

        var finalStatus = report.status
        var failureReason: String?

        if !missing.isEmpty {
            finalStatus = .corruptedOrTampered
            failureReason = "Missing \(missing.count) linkage binaries or libraries: \(missing.prefix(3).joined(separator: ", "))"
        } else if checksums.contains(where: { $0.sizeBytes == 0 }) {
            finalStatus = .corruptedOrTampered
            failureReason = "Detected empty / truncated 0-byte binaries in installation"
        }

        return BottleIntegrityReport(
            packageID: report.packageID,
            packageName: report.packageName,
            version: report.version,
            status: finalStatus,
            bottleSHA256: report.bottleSHA256,
            bottleArch: report.bottleArch,
            compiler: report.compiler,
            sourceModified: report.sourceModified,
            pouredFromBottle: report.pouredFromBottle,
            installedFilesCount: totalCount,
            binaryChecksums: checksums,
            missingFiles: missing,
            failureReason: failureReason
        )
    }

    // MARK: - Receipt Parsing

    nonisolated static func parseReceiptJSON(
        _ json: [String: Any],
        packageID: String,
        packageName: String? = nil,
        version: String = "installed"
    ) -> BottleIntegrityReport {
        let sourceModified = (json["source_modified"] as? Bool) ?? false
        let compiler = (json["compiler"] as? String) ?? "clang"
        let builtAsBottle = (json["built_as_bottle"] as? Bool) ?? true
        let pouredFromBottle = (json["poured_from_bottle"] as? Bool) ?? builtAsBottle

        var sha256: String?
        var arch: String?

        if let bottleDict = json["bottle"] as? [String: Any],
           let files = bottleDict["files"] as? [String: Any] {
            for (key, fileInfo) in files {
                arch = key
                if let dict = fileInfo as? [String: Any], let hash = dict["sha256"] as? String {
                    sha256 = hash
                    break
                }
            }
        }

        let status: BottleIntegrityStatus = builtAsBottle ? .verifiedBottle : .builtFromSource

        return BottleIntegrityReport(
            packageID: packageID,
            packageName: packageName ?? packageID,
            version: version,
            status: status,
            bottleSHA256: sha256,
            bottleArch: arch,
            compiler: compiler,
            sourceModified: sourceModified,
            pouredFromBottle: pouredFromBottle
        )
    }

    // MARK: - Cellar Binary & Linkage Verification

    nonisolated private static func inspectCellarFiles(
        versionDir: URL,
        receiptJson: [String: Any]
    ) -> (checksums: [BinaryChecksumItem], missing: [String], totalCount: Int) {
        let fm = FileManager.default
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useMB, .useKB, .useBytes]
        byteFormatter.countStyle = .file

        var checksums: [BinaryChecksumItem] = []
        var missing: [String] = []
        var totalFiles = 0

        // 1. Inspect declared linkage files if present in receipt
        if let linkageFiles = receiptJson["linkage_files"] as? [String] {
            for relPath in linkageFiles {
                let fileURL = versionDir.appendingPathComponent(relPath)
                if fm.fileExists(atPath: fileURL.path) {
                    let attr = try? fm.attributesOfItem(atPath: fileURL.path)
                    let size = (attr?[.size] as? Int64) ?? 0
                    let hash = computeFileSHA256(at: fileURL) ?? "unreadable"
                    checksums.append(BinaryChecksumItem(
                        id: relPath,
                        relativePath: relPath,
                        fullPath: fileURL.path,
                        sizeBytes: size,
                        formattedSize: byteFormatter.string(fromByteCount: size),
                        sha256: hash,
                        isMachO: true,
                        exists: true
                    ))
                } else {
                    missing.append(relPath)
                }
            }
        }

        // 2. Also inspect bin/ directory if present
        let binURL = versionDir.appendingPathComponent("bin")
        if let binFiles = try? fm.contentsOfDirectory(at: binURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for file in binFiles {
                let rel = "bin/\(file.lastPathComponent)"
                if !checksums.contains(where: { $0.relativePath == rel }) {
                    let attr = try? fm.attributesOfItem(atPath: file.path)
                    let size = (attr?[.size] as? Int64) ?? 0
                    let hash = computeFileSHA256(at: file) ?? "unreadable"
                    checksums.append(BinaryChecksumItem(
                        id: rel,
                        relativePath: rel,
                        fullPath: file.path,
                        sizeBytes: size,
                        formattedSize: byteFormatter.string(fromByteCount: size),
                        sha256: hash,
                        isMachO: true,
                        exists: true
                    ))
                }
            }
        }

        // 3. Count total files
        if let enumerator = fm.enumerator(at: versionDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for _ in enumerator {
                totalFiles += 1
            }
        }

        return (checksums, missing, totalFiles)
    }

    // MARK: - Batch System Audit

    func auditAllInstalled(prefix: String, packages: [BrewStorePackage]) {
        guard !isAuditing else { return }
        isAuditing = true
        auditError = nil

        Task.detached(priority: .userInitiated) {
            let formulae = packages.filter { $0.kind == .formula && $0.isInstalled }
            var reports: [BottleIntegrityReport] = []
            var verified = 0
            var builtFromSource = 0
            var corrupted = 0
            var unmanaged = 0

            for pkg in formulae {
                let rep = Self.auditPackage(package: pkg, prefix: prefix)
                reports.append(rep)
                switch rep.status {
                case .verifiedBottle:
                    verified += 1
                case .builtFromSource:
                    builtFromSource += 1
                case .corruptedOrTampered:
                    corrupted += 1
                case .unmanagedOrManual:
                    unmanaged += 1
                }
            }

            // Sort: issues first (corrupted then unmanaged), then alphabetical
            reports.sort { a, b in
                if a.hasIntegrityIssue != b.hasIntegrityIssue {
                    return a.hasIntegrityIssue && !b.hasIntegrityIssue
                }
                return a.packageName.localizedStandardCompare(b.packageName) == .orderedAscending
            }

            let summary = SystemBottleAuditSummary(
                reports: reports,
                verifiedCount: verified,
                builtFromSourceCount: builtFromSource,
                corruptedCount: corrupted,
                unmanagedCount: unmanaged,
                scannedAt: Date()
            )

            await MainActor.run {
                self.summary = summary
                self.isAuditing = false
            }
        }
    }

    // MARK: - Remediation Actions

    func reinstallBottle(packageID: String, prefix: String, manager: HomebrewManager? = nil) async -> (success: Bool, message: String) {
        guard operatingPackageID == nil else { return (false, "Another operation is in progress.") }
        operatingPackageID = packageID
        defer { operatingPackageID = nil }

        let brewPath = manager?.brewPath ?? ((prefix as NSString).appendingPathComponent("bin") as NSString).appendingPathComponent("brew")
        let result = commandExecutor.run(
            executablePath: brewPath,
            arguments: ["reinstall", "--force-bottle", packageID],
            timeout: 120,
            category: .destructiveMutation
        )

        if result.succeeded {
            manager?.refresh()
            return (true, "Reinstalled fresh verified bottle for \(packageID).")
        } else {
            let msg = BrewStoreHumanizedErrorResolver.humanizedMessage(from: result.standardError, fallback: "Reinstallation failed for \(packageID).")
            auditError = msg
            return (false, msg)
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
