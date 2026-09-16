import AppKit
import Foundation

enum SnapshotBackupFrequency: String, CaseIterable, Identifiable, Codable {
    case manual = "Manual"
    case daily = "Daily"
    case weekly = "Weekly (Recommended)"
    case monthly = "Monthly"

    var id: String {
        rawValue
    }

    var intervalSeconds: TimeInterval {
        switch self {
        case .manual: 0
        case .daily: 86400
        case .weekly: 604800
        case .monthly: 2592000
        }
    }
}

struct BrewStoreSnapshot: Identifiable, Hashable, Codable {
    let id: String
    let timestamp: Date
    let name: String
    let fileURL: URL
    let formulae: [String]
    let casks: [String]
    let taps: [String]

    var totalCount: Int {
        formulae.count + casks.count
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

struct BrewStoreSnapshotDiff: Hashable {
    let snapshot: BrewStoreSnapshot
    let addedFormulae: [String]
    let addedCasks: [String]
    let missingFormulae: [String]
    let missingCasks: [String]
    let missingTaps: [String]
    let identicalCount: Int

    var hasDifferences: Bool {
        !addedFormulae.isEmpty || !addedCasks.isEmpty || !missingFormulae.isEmpty || !missingCasks.isEmpty || !missingTaps.isEmpty
    }

    var totalChanges: Int {
        addedFormulae.count + addedCasks.count + missingFormulae.count + missingCasks.count + missingTaps.count
    }
}

@MainActor
final class BrewStoreSnapshotManager: ObservableObject {
    @Published var snapshots: [BrewStoreSnapshot] = []
    @Published var backupFrequency: SnapshotBackupFrequency {
        didSet {
            UserDefaults.standard.set(backupFrequency.rawValue, forKey: "brewstore.snapshot.backup_frequency")
        }
    }

    @Published var lastScheduledBackupDate: Date? {
        didSet {
            if let lastScheduledBackupDate {
                UserDefaults.standard.set(lastScheduledBackupDate.timeIntervalSince1970, forKey: "brewstore.snapshot.last_scheduled_backup")
            }
        }
    }

    private let fileManager = FileManager.default
    private let snapshotsDirectory: URL

    init(directory: URL? = nil) {
        let savedFreq = UserDefaults.standard.string(forKey: "brewstore.snapshot.backup_frequency") ?? SnapshotBackupFrequency.weekly.rawValue
        self.backupFrequency = SnapshotBackupFrequency(rawValue: savedFreq) ?? .weekly
        let savedDate = UserDefaults.standard.double(forKey: "brewstore.snapshot.last_scheduled_backup")
        self.lastScheduledBackupDate = savedDate > 0 ? Date(timeIntervalSince1970: savedDate) : nil

        if let directory {
            self.snapshotsDirectory = directory
        } else if let fixtureDir = BrewStoreFixtureMode.customSnapshotsDirectory {
            self.snapshotsDirectory = fixtureDir
        } else {
            let baseDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let support = baseDir
                .appendingPathComponent("BrewStore", isDirectory: true)
                .appendingPathComponent("Snapshots", isDirectory: true)
            self.snapshotsDirectory = support
        }
        try? fileManager.createDirectory(at: self.snapshotsDirectory, withIntermediateDirectories: true)
        loadSnapshots()
    }

    func loadSnapshots() {
        guard let files = try? fileManager.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: [.creationDateKey]) else { return }

        var results: [BrewStoreSnapshot] = []
        for file in files where file.pathExtension == "brewfile" || file.lastPathComponent.hasPrefix("Brewfile") {
            let content = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let parsed = BrewStoreBrewfileParser.parse(content)
            let date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let id = file.deletingPathExtension().lastPathComponent

            let snapshot = BrewStoreSnapshot(
                id: id,
                timestamp: date,
                name: id.replacingOccurrences(of: "Brewfile-", with: "").replacingOccurrences(of: "-", with: " "),
                fileURL: file,
                formulae: Array(parsed.formulae).sorted(),
                casks: Array(parsed.casks).sorted(),
                taps: Array(parsed.taps).sorted()
            )
            results.append(snapshot)
        }

        self.snapshots = results.sorted { $0.timestamp > $1.timestamp }
    }

    func createSnapshot(name _: String? = nil, manager: HomebrewManager) {
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let dateStr = formatter.string(from: timestamp)
        let filename = "Brewfile-\(dateStr)"
        let fileURL = snapshotsDirectory.appendingPathComponent(filename)

        let installedPackages = manager.packages.filter(\.isInstalled)
        let content = BrewStoreBrewfileParser.generate(packages: installedPackages, taps: manager.taps)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            loadSnapshots()
        } catch {
            print("Failed to write snapshot: \(error)")
        }
    }

    func deleteSnapshot(_ snapshot: BrewStoreSnapshot) {
        try? fileManager.removeItem(at: snapshot.fileURL)
        loadSnapshots()
    }

    func computeDiff(for snapshot: BrewStoreSnapshot, currentPackages: [BrewStorePackage], currentTaps: [BrewStoreTap]) -> BrewStoreSnapshotDiff {
        let currentFormulae = Set(currentPackages.filter { $0.kind == .formula && $0.isInstalled }.map(\.id))
        let currentCasks = Set(currentPackages.filter { $0.kind == .cask && $0.isInstalled }.map(\.id))
        let currentTapsSet = Set(currentTaps.map(\.name))

        let snapshotFormulae = Set(snapshot.formulae)
        let snapshotCasks = Set(snapshot.casks)
        let snapshotTaps = Set(snapshot.taps)

        let addedFormulae = Array(currentFormulae.subtracting(snapshotFormulae)).sorted()
        let addedCasks = Array(currentCasks.subtracting(snapshotCasks)).sorted()

        let missingFormulae = Array(snapshotFormulae.subtracting(currentFormulae)).sorted()
        let missingCasks = Array(snapshotCasks.subtracting(currentCasks)).sorted()
        let missingTaps = Array(snapshotTaps.subtracting(currentTapsSet)).sorted()

        let identicalFormulae = currentFormulae.intersection(snapshotFormulae).count
        let identicalCasks = currentCasks.intersection(snapshotCasks).count

        return BrewStoreSnapshotDiff(
            snapshot: snapshot,
            addedFormulae: addedFormulae,
            addedCasks: addedCasks,
            missingFormulae: missingFormulae,
            missingCasks: missingCasks,
            missingTaps: missingTaps,
            identicalCount: identicalFormulae + identicalCasks
        )
    }

    func checkScheduledBackup(manager: HomebrewManager) {
        guard backupFrequency != .manual else { return }
        let now = Date()
        let interval = backupFrequency.intervalSeconds
        let referenceDate = lastScheduledBackupDate ?? snapshots.first?.timestamp

        if let referenceDate {
            if now.timeIntervalSince(referenceDate) >= interval {
                createSnapshot(name: "Scheduled Auto-Backup", manager: manager)
                lastScheduledBackupDate = now
            }
        } else {
            createSnapshot(name: "Initial Auto-Backup", manager: manager)
            lastScheduledBackupDate = now
        }
    }

    @discardableResult
    func exportBrewfile(content: String, defaultName: String = "Brewfile") -> Bool {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Brewfile"
        savePanel.prompt = "Export"
        savePanel.nameFieldStringValue = defaultName.hasSuffix(".brewfile") || defaultName.hasSuffix("Brewfile") ? defaultName : "\(defaultName).brewfile"
        savePanel.canCreateDirectories = true

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }
        return false
    }

    @discardableResult
    func exportSnapshot(_ snapshot: BrewStoreSnapshot) -> Bool {
        guard let content = try? String(contentsOf: snapshot.fileURL, encoding: .utf8) else { return false }
        return exportBrewfile(content: content, defaultName: "\(snapshot.id).brewfile")
    }

    @discardableResult
    func exportCurrentState(manager: HomebrewManager) -> Bool {
        let installedPackages = manager.packages.filter(\.isInstalled)
        let content = BrewStoreBrewfileParser.generate(packages: installedPackages, taps: manager.taps)
        return exportBrewfile(content: content, defaultName: "Brewfile")
    }
}
