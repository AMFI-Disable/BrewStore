import Foundation

struct StorageItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let kind: BrewPackageKind
    let sizeBytes: Int64
    let formattedSize: String
    let percentageOfTotal: Double
    let path: String
}

struct StorageReport: Hashable, Codable {
    let totalCellarBytes: Int64
    let totalCacheBytes: Int64
    let totalLogsBytes: Int64
    let inactiveVersionsBytes: Int64
    let items: [StorageItem]
    let topHogs: [StorageItem]

    init(totalCellarBytes: Int64, totalCacheBytes: Int64, totalLogsBytes: Int64 = 0, inactiveVersionsBytes: Int64 = 0, items: [StorageItem], topHogs: [StorageItem]) {
        self.totalCellarBytes = totalCellarBytes
        self.totalCacheBytes = totalCacheBytes
        self.totalLogsBytes = totalLogsBytes
        self.inactiveVersionsBytes = inactiveVersionsBytes
        self.items = items
        self.topHogs = topHogs
    }

    var reclaimableBytes: Int64 {
        totalCacheBytes + totalLogsBytes + inactiveVersionsBytes
    }

    var formattedTotalCellar: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: totalCellarBytes)
    }

    var formattedTotalCache: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: totalCacheBytes)
    }

    var formattedTotalLogs: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: totalLogsBytes)
    }

    var formattedInactiveVersions: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: inactiveVersionsBytes)
    }

    var formattedReclaimable: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: reclaimableBytes)
    }
}

@MainActor
final class BrewStoreDiskStorageAnalyzerManager: ObservableObject {
    static let shared = BrewStoreDiskStorageAnalyzerManager()

    @Published var report: StorageReport?
    @Published var isScanning = false

    func scanStorage(manager: HomebrewManager) {
        isScanning = true
        let prefix = manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")

        Task.detached(priority: .userInitiated) {
            let result = Self.computeStorageReport(prefix: prefix)
            await MainActor.run {
                self.report = result
                self.isScanning = false
            }
        }
    }

    func purgeCache(manager: HomebrewManager) {
        guard let brewPath = manager.brewPath else { return }
        Task.detached(priority: .userInitiated) {
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["cleanup", "--prune=all"],
                timeout: 30
            )

            await MainActor.run {
                self.scanStorage(manager: manager)
            }
        }
    }

    func purgeLogs(manager: HomebrewManager) {
        Task.detached(priority: .userInitiated) {
            let logsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Homebrew")
            if let files = try? FileManager.default.contentsOfDirectory(at: logsURL, includingPropertiesForKeys: nil) {
                for file in files {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            await MainActor.run {
                self.scanStorage(manager: manager)
            }
        }
    }

    func purgeInactiveVersions(manager: HomebrewManager) {
        guard let brewPath = manager.brewPath else { return }
        Task.detached(priority: .userInitiated) {
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["cleanup", "-s"],
                timeout: 30
            )

            await MainActor.run {
                self.scanStorage(manager: manager)
            }
        }
    }

    func purgeDeepCaches(manager: HomebrewManager) {
        guard let brewPath = manager.brewPath else { return }
        Task.detached(priority: .userInitiated) {
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["cleanup", "--prune=all", "-s"],
                timeout: 45
            )
            let logsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Homebrew")
            if let files = try? FileManager.default.contentsOfDirectory(at: logsURL, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                for file in files {
                    if file.path.hasPrefix(logsURL.path), (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
            await MainActor.run {
                self.scanStorage(manager: manager)
            }
        }
    }

    nonisolated static func computeStorageReport(prefix: String) -> StorageReport {
        let fm = FileManager.default
        let cellarURL = URL(fileURLWithPath: prefix).appendingPathComponent("Cellar")
        let caskroomURL = URL(fileURLWithPath: prefix).appendingPathComponent("Caskroom")
        let cacheURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Homebrew")
        let logsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Homebrew")

        var scannedItems: [(id: String, name: String, kind: BrewPackageKind, size: Int64, path: String)] = []
        var totalCellarSize: Int64 = 0
        var inactiveVersionsBytes: Int64 = 0

        // 1. Scan Cellar & Inactive Versions
        if let cellarContents = try? fm.contentsOfDirectory(at: cellarURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for dir in cellarContents {
                let size = computeDirectorySize(url: dir)
                if size > 0 {
                    totalCellarSize += size
                    scannedItems.append((id: dir.lastPathComponent, name: dir.lastPathComponent, kind: .formula, size: size, path: dir.path))
                }

                // Check for multi-version folders
                if let versionDirs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    let nonMeta = versionDirs.filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "INSTALL_RECEIPT.json" && $0.lastPathComponent != ".brew" }
                    if nonMeta.count > 1 {
                        // Count all but the newest as inactive
                        let sorted = nonMeta.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                        for oldVer in sorted.dropFirst() {
                            inactiveVersionsBytes += computeDirectorySize(url: oldVer)
                        }
                    }
                }
            }
        }

        // 2. Scan Caskroom
        if let caskContents = try? fm.contentsOfDirectory(at: caskroomURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for dir in caskContents {
                let size = computeDirectorySize(url: dir)
                if size > 0 {
                    totalCellarSize += size
                    scannedItems.append((id: dir.lastPathComponent, name: dir.lastPathComponent, kind: .cask, size: size, path: dir.path))
                }
            }
        }

        // 3. Scan Cache & Logs
        let totalCacheSize = computeDirectorySize(url: cacheURL)
        let totalLogsSize = computeDirectorySize(url: logsURL)

        // Map into StorageItem with percentages
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file

        let storageItems: [StorageItem] = scannedItems.map { item in
            let pct = totalCellarSize > 0 ? Double(item.size) / Double(totalCellarSize) : 0.0
            return StorageItem(
                id: item.id,
                name: item.name,
                kind: item.kind,
                sizeBytes: item.size,
                formattedSize: formatter.string(fromByteCount: item.size),
                percentageOfTotal: pct,
                path: item.path
            )
        }.sorted { $0.sizeBytes > $1.sizeBytes }

        return StorageReport(
            totalCellarBytes: totalCellarSize,
            totalCacheBytes: totalCacheSize,
            totalLogsBytes: totalLogsSize,
            inactiveVersionsBytes: inactiveVersionsBytes,
            items: storageItems,
            topHogs: Array(storageItems.prefix(5))
        )
    }

    nonisolated static func computeDirectorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else {
                continue
            }
            totalSize += Int64(size)
        }
        return totalSize
    }
}
