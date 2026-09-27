import Foundation
import Combine

struct KegInstalledVersion: Identifiable, Hashable, Sendable, Codable {
    var id: String { version }
    let version: String
    let path: String
    let isCurrentlyLinked: Bool
    let installedDate: Date?
    let sizeBytes: Int64

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct KegSnapshotArchive: Identifiable, Hashable, Sendable, Codable {
    var id: String { filename }
    let filename: String
    let packageID: String
    let version: String
    let createdAt: Date
    let filePath: String
    let sizeBytes: Int64

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct KegPackageState: Identifiable, Hashable, Sendable {
    var id: String { packageID }
    let packageID: String
    let installedVersions: [KegInstalledVersion]
    let snapshots: [KegSnapshotArchive]
    let activeLinkedVersion: String?

    var hasMultipleVersionsOrSnapshots: Bool {
        installedVersions.count > 1 || !snapshots.isEmpty
    }
}

enum KegSnapshotError: LocalizedError, Sendable {
    case packageNotInstalled(String)
    case versionNotFound(String)
    case archivingFailed(String)
    case restorationFailed(String)
    case unlinkingFailed(String)
    case linkingFailed(String)
    case securityViolation(String)

    var errorDescription: String? {
        switch self {
        case let .packageNotInstalled(id):
            return "Package '\(id)' has no Cellar directory."
        case let .versionNotFound(v):
            return "Version directory '\(v)' was not found in the Cellar."
        case let .archivingFailed(msg):
            return "Failed to create keg snapshot archive: \(msg)"
        case let .restorationFailed(msg):
            return "Failed to restore keg snapshot: \(msg)"
        case let .unlinkingFailed(msg):
            return "Failed to unlink active keg: \(msg)"
        case let .linkingFailed(msg):
            return "Failed to link target version: \(msg)"
        case let .securityViolation(msg):
            return "Security boundary violation: \(msg)"
        }
    }
}

@MainActor
final class KegSnapshotManager: ObservableObject {
    static let shared = KegSnapshotManager()

    @Published private(set) var stateByPackage: [String: KegPackageState] = [:]
    @Published private(set) var isOperating: Bool = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?

    private let fileManager = FileManager.default
    private let commandExecutor: BrewStoreCommandExecutor

    init(commandExecutor: BrewStoreCommandExecutor = .shared) {
        self.commandExecutor = commandExecutor
    }

    // MARK: - Directory Path Resolvers

    func baseSnapshotsDirectory() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let snapshotsURL = appSupport.appendingPathComponent("BrewStore/KegSnapshots", isDirectory: true)
        if !fileManager.fileExists(atPath: snapshotsURL.path) {
            try? fileManager.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        }
        return snapshotsURL
    }

    func packageSnapshotsDirectory(for packageID: String) -> URL {
        let dir = baseSnapshotsDirectory().appendingPathComponent(packageID, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func defaultBrewPrefix() -> String {
        if fileManager.fileExists(atPath: "/opt/homebrew") {
            return "/opt/homebrew"
        }
        return "/usr/local"
    }

    func cellarDirectory(for packageID: String, prefix: String? = nil) -> URL {
        let p = prefix ?? defaultBrewPrefix()
        return URL(fileURLWithPath: p).appendingPathComponent("Cellar").appendingPathComponent(packageID, isDirectory: true)
    }

    func linkedKegRecord(for packageID: String, prefix: String? = nil) -> URL {
        let p = prefix ?? defaultBrewPrefix()
        return URL(fileURLWithPath: p).appendingPathComponent("var/homebrew/linked").appendingPathComponent(packageID)
    }

    func optDirectory(for packageID: String, prefix: String? = nil) -> URL {
        let p = prefix ?? defaultBrewPrefix()
        return URL(fileURLWithPath: p).appendingPathComponent("opt").appendingPathComponent(packageID)
    }

    func binDirectory(prefix: String? = nil) -> URL {
        let p = prefix ?? defaultBrewPrefix()
        return URL(fileURLWithPath: p).appendingPathComponent("bin", isDirectory: true)
    }

    // MARK: - Detection & State Fetching

    func detectActiveVersion(for packageID: String, prefix: String? = nil) -> String? {
        let linkedURL = linkedKegRecord(for: packageID, prefix: prefix)
        if let dest = try? fileManager.destinationOfSymbolicLink(atPath: linkedURL.path) {
            let last = URL(fileURLWithPath: dest).lastPathComponent
            if !last.isEmpty && last != "." && last != ".." {
                return last
            }
        }

        let optURL = optDirectory(for: packageID, prefix: prefix)
        if let dest = try? fileManager.destinationOfSymbolicLink(atPath: optURL.path) {
            let last = URL(fileURLWithPath: dest).lastPathComponent
            if !last.isEmpty && last != "." && last != ".." {
                return last
            }
        }

        return nil
    }

    func scanPackageKegs(for packageID: String, prefix: String? = nil) -> KegPackageState {
        let cellarDir = cellarDirectory(for: packageID, prefix: prefix)
        let activeVersion = detectActiveVersion(for: packageID, prefix: prefix)

        var installedVersions: [KegInstalledVersion] = []
        if let contents = try? fileManager.contentsOfDirectory(at: cellarDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles) {
            for item in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let version = item.lastPathComponent
                    let isLinked = (version == activeVersion)
                    let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    let size = calculateDirectorySize(at: item)

                    installedVersions.append(KegInstalledVersion(
                        version: version,
                        path: item.path,
                        isCurrentlyLinked: isLinked,
                        installedDate: modDate,
                        sizeBytes: size
                    ))
                }
            }
        }

        installedVersions.sort { $0.version.compare($1.version, options: .numeric) == .orderedDescending }

        // Snapshots
        let snapDir = packageSnapshotsDirectory(for: packageID)
        var snapshots: [KegSnapshotArchive] = []
        if let files = try? fileManager.contentsOfDirectory(at: snapDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles) {
            for file in files where file.pathExtension == "gz" {
                let filename = file.lastPathComponent
                let attrs = try? fileManager.attributesOfItem(atPath: file.path)
                let date = attrs?[.creationDate] as? Date ?? Date()
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

                // Parse version from filename: "<pkg>-<ver>-<timestamp>.tar.gz"
                let stripped = filename.replacingOccurrences(of: ".tar.gz", with: "")
                let components = stripped.split(separator: "-")
                let ver: String
                if components.count >= 3 {
                    ver = String(components[1])
                } else if components.count >= 2 {
                    ver = String(components[1])
                } else {
                    ver = "unknown"
                }

                snapshots.append(KegSnapshotArchive(
                    filename: filename,
                    packageID: packageID,
                    version: ver,
                    createdAt: date,
                    filePath: file.path,
                    sizeBytes: size
                ))
            }
        }
        snapshots.sort { $0.createdAt > $1.createdAt }

        let state = KegPackageState(
            packageID: packageID,
            installedVersions: installedVersions,
            snapshots: snapshots,
            activeLinkedVersion: activeVersion
        )
        self.stateByPackage[packageID] = state
        return state
    }

    private func calculateDirectorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Snapshot Operations

    func createSnapshot(packageID: String, version: String, prefix: String? = nil) async throws -> KegSnapshotArchive {
        isOperating = true
        statusMessage = "Creating snapshot for \(packageID) v\(version)…"
        lastError = nil
        defer {
            isOperating = false
            statusMessage = nil
        }

        let cellarDir = cellarDirectory(for: packageID, prefix: prefix)
        let versionDir = cellarDir.appendingPathComponent(version)
        guard fileManager.fileExists(atPath: versionDir.path) else {
            let err = KegSnapshotError.versionNotFound(version)
            lastError = err.localizedDescription
            throw err
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let archiveFilename = "\(packageID)-\(version)-\(timestamp).tar.gz"
        let destURL = packageSnapshotsDirectory(for: packageID).appendingPathComponent(archiveFilename)

        // Execute /usr/bin/tar -czf <dest> -C <cellarDir> <version>
        let result = commandExecutor.run(
            executablePath: "/usr/bin/tar",
            arguments: ["-czf", destURL.path, "-C", cellarDir.path, version],
            timeout: 60,
            category: .reversibleMutation
        )

        guard result.succeeded, fileManager.fileExists(atPath: destURL.path) else {
            let err = KegSnapshotError.archivingFailed(result.standardError.isEmpty ? "Tar execution failed" : result.standardError)
            lastError = err.localizedDescription
            throw err
        }

        let attrs = try? fileManager.attributesOfItem(atPath: destURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

        let snapshot = KegSnapshotArchive(
            filename: archiveFilename,
            packageID: packageID,
            version: version,
            createdAt: Date(),
            filePath: destURL.path,
            sizeBytes: size
        )

        _ = scanPackageKegs(for: packageID, prefix: prefix)
        return snapshot
    }

    func restoreSnapshot(archive: KegSnapshotArchive, prefix: String? = nil) async throws {
        isOperating = true
        statusMessage = "Restoring \(archive.packageID) v\(archive.version) from archive…"
        lastError = nil
        defer {
            isOperating = false
            statusMessage = nil
        }

        guard fileManager.fileExists(atPath: archive.filePath) else {
            let err = KegSnapshotError.restorationFailed("Archive file not found at \(archive.filePath)")
            lastError = err.localizedDescription
            throw err
        }

        let cellarDir = cellarDirectory(for: archive.packageID, prefix: prefix)
        try? fileManager.createDirectory(at: cellarDir, withIntermediateDirectories: true)

        let result = commandExecutor.run(
            executablePath: "/usr/bin/tar",
            arguments: ["-xzf", archive.filePath, "-C", cellarDir.path],
            timeout: 60,
            category: .reversibleMutation
        )

        guard result.succeeded else {
            let err = KegSnapshotError.restorationFailed(result.standardError.isEmpty ? "Tar extraction failed" : result.standardError)
            lastError = err.localizedDescription
            throw err
        }

        _ = scanPackageKegs(for: archive.packageID, prefix: prefix)
    }

    func deleteSnapshot(archive: KegSnapshotArchive, prefix: String? = nil) throws {
        if fileManager.fileExists(atPath: archive.filePath) {
            try fileManager.removeItem(atPath: archive.filePath)
        }
        _ = scanPackageKegs(for: archive.packageID, prefix: prefix)
    }

    // MARK: - Rollback Execution

    func rollback(
        packageID: String,
        to targetVersion: String,
        prefix: String? = nil,
        homebrewManager: HomebrewManager? = nil
    ) async throws {
        isOperating = true
        statusMessage = "Rolling back \(packageID) to v\(targetVersion)…"
        lastError = nil
        defer {
            isOperating = false
            statusMessage = nil
        }

        let p = prefix ?? defaultBrewPrefix()
        let cellarDir = cellarDirectory(for: packageID, prefix: p)
        let targetVersionDir = cellarDir.appendingPathComponent(targetVersion)

        // 1. If target version isn't in Cellar, check if we have a snapshot to restore
        if !fileManager.fileExists(atPath: targetVersionDir.path) {
            let currentSnapshots = stateByPackage[packageID]?.snapshots ?? []
            if let matchingSnapshot = currentSnapshots.first(where: { $0.version == targetVersion }) {
                try await restoreSnapshot(archive: matchingSnapshot, prefix: p)
            } else {
                let err = KegSnapshotError.versionNotFound(targetVersion)
                lastError = err.localizedDescription
                throw err
            }
        }

        // 2. Unlink existing version via brew command
        let brewBinary = URL(fileURLWithPath: p).appendingPathComponent("bin/brew").path
        let unlinkResult = commandExecutor.run(
            executablePath: brewBinary,
            arguments: ["unlink", packageID],
            timeout: 30,
            category: .reversibleMutation
        )
        // If unlink fails because nothing is linked, that is fine, continue.
        _ = unlinkResult

        // 3. Atomically point opt/<packageID> to target version
        let optURL = optDirectory(for: packageID, prefix: p)
        try? fileManager.removeItem(at: optURL)
        let relOptDest = "../Cellar/\(packageID)/\(targetVersion)"
        do {
            try fileManager.createSymbolicLink(atPath: optURL.path, withDestinationPath: relOptDest)
        } catch {
            let err = KegSnapshotError.linkingFailed("Failed to update opt symlink: \(error.localizedDescription)")
            lastError = err.localizedDescription
            throw err
        }

        // 4. Update var/homebrew/linked/<packageID>
        let linkedURL = linkedKegRecord(for: packageID, prefix: p)
        let linkedParent = linkedURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: linkedParent, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: linkedURL)
        let relLinkedDest = "../../../Cellar/\(packageID)/\(targetVersion)"
        try? fileManager.createSymbolicLink(atPath: linkedURL.path, withDestinationPath: relLinkedDest)

        // 5. Link binaries from target version into <prefix>/bin
        let targetBinDir = targetVersionDir.appendingPathComponent("bin")
        let globalBinDir = binDirectory(prefix: p)
        if fileManager.fileExists(atPath: targetBinDir.path),
           let binItems = try? fileManager.contentsOfDirectory(at: targetBinDir, includingPropertiesForKeys: nil) {
            for item in binItems {
                let binaryName = item.lastPathComponent
                let destSymlink = globalBinDir.appendingPathComponent(binaryName)
                try? fileManager.removeItem(at: destSymlink)
                try? fileManager.createSymbolicLink(at: destSymlink, withDestinationURL: item)
            }
        }

        // 6. Refresh manager if provided
        homebrewManager?.refresh()

        _ = scanPackageKegs(for: packageID, prefix: p)
    }
}
