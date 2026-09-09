import Foundation

@MainActor
final class BrewStoreDotfilesAutoSyncManager: ObservableObject {
    static let shared = BrewStoreDotfilesAutoSyncManager()

    private let enabledKey = "brewstore.dotfiles.autosync.enabled"
    private let pathKey = "brewstore.dotfiles.brewfile.path"

    @Published var isAutoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSyncEnabled, forKey: enabledKey)
        }
    }

    @Published var customBrewfilePath: String {
        didSet {
            UserDefaults.standard.set(customBrewfilePath, forKey: pathKey)
        }
    }

    @Published var lastSyncDate: Date?
    @Published var lastSyncStatus: String?

    init() {
        self.isAutoSyncEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        let defaultPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Brewfile")
        self.customBrewfilePath = UserDefaults.standard.string(forKey: pathKey) ?? defaultPath
    }

    var resolvedURL: URL {
        let expanded = (customBrewfilePath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    func syncNow(manager: HomebrewManager) {
        guard manager.isAvailable else { return }

        let installed = manager.packages.filter(\.isInstalled)
        let formulae = installed.filter { $0.kind == .formula }.sorted(by: { $0.id < $1.id })
        let casks = installed.filter { $0.kind == .cask }.sorted(by: { $0.id < $1.id })
        let taps = manager.taps.sorted(by: { $0.name < $1.name })

        var lines = [
            "# Auto-generated Brewfile by BrewStore",
            "# Last Synced: \(Date().formatted(date: .abbreviated, time: .standard))",
            ""
        ]

        if !taps.isEmpty {
            lines.append("# --- Taps ---")
            for tap in taps {
                let sanitizedTap = tap.name.replacingOccurrences(of: "\"", with: "\\\"")
                lines.append("tap \"\(sanitizedTap)\"")
            }
            lines.append("")
        }

        if !formulae.isEmpty {
            lines.append("# --- Formulae ---")
            for f in formulae {
                let sanitizedFormula = f.id.replacingOccurrences(of: "\"", with: "\\\"")
                lines.append("brew \"\(sanitizedFormula)\"")
            }
            lines.append("")
        }

        if !casks.isEmpty {
            lines.append("# --- Casks ---")
            for c in casks {
                let sanitizedCask = c.id.replacingOccurrences(of: "\"", with: "\\\"")
                lines.append("cask \"\(sanitizedCask)\"")
            }
            lines.append("")
        }

        let content = lines.joined(separator: "\n")
        let targetURL = resolvedURL

        do {
            let parentDir = targetURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
            self.lastSyncDate = Date()
            self.lastSyncStatus = "Successfully synced \(formulae.count + casks.count) packages to \(targetURL.lastPathComponent)"
        } catch {
            self.lastSyncStatus = "Sync failed: \(error.localizedDescription)"
        }
    }

    func onPackageOperationCompleted(manager: HomebrewManager) {
        if isAutoSyncEnabled {
            syncNow(manager: manager)
        }
    }
}
