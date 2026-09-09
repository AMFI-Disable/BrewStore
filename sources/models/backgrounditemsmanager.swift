import AppKit
import Foundation

enum BackgroundItemKind: String, Codable, CaseIterable, Sendable {
    case userLaunchAgent = "User Launch Agent"
    case systemLaunchAgent = "System Launch Agent"
    case loginItem = "Login Item"
}

struct BrewStoreBackgroundItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let label: String
    let programPath: String?
    let plistURL: URL?
    let kind: BackgroundItemKind
    let associatedAppName: String?
    let isLoaded: Bool
    let isRunning: Bool
    let runAtLoad: Bool
    let pid: Int?

    var displayName: String {
        if !name.isEmpty, name != label {
            return name
        }
        if let app = associatedAppName, !app.isEmpty {
            return "\(app) Helper"
        }
        return label
    }
}

@MainActor
final class BrewStoreBackgroundItemsManager: ObservableObject {
    static let shared = BrewStoreBackgroundItemsManager()

    @Published var items: [BrewStoreBackgroundItem] = []
    @Published var isScanning = false
    @Published var statusMessage: String?

    func scanBackgroundItems() {
        isScanning = true
        statusMessage = nil

        Task.detached(priority: .userInitiated) {
            let loadedMap = Self.fetchLoadedLaunchctlMap()
            var detected: [BrewStoreBackgroundItem] = []

            // 1. Scan User LaunchAgents (~/Library/LaunchAgents)
            let userAgentsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents")
            detected.append(contentsOf: Self.scanAgentsDirectory(userAgentsDir, kind: .userLaunchAgent, loadedMap: loadedMap))

            // 2. Scan System LaunchAgents (/Library/LaunchAgents)
            let sysAgentsDir = URL(fileURLWithPath: "/Library/LaunchAgents")
            detected.append(contentsOf: Self.scanAgentsDirectory(sysAgentsDir, kind: .systemLaunchAgent, loadedMap: loadedMap))

            // 3. Scan Login Items via System Events
            let loginItems = Self.fetchLoginItems()
            detected.append(contentsOf: loginItems)

            // Sort: Running / Loaded first, then alphabetically
            let sorted = detected.sorted { a, b in
                if a.isRunning != b.isRunning {
                    return a.isRunning && !b.isRunning
                }
                if a.isLoaded != b.isLoaded {
                    return a.isLoaded && !b.isLoaded
                }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }

            await MainActor.run { [weak self] in
                self?.items = sorted
                self?.isScanning = false
            }
        }
    }

    func toggleItem(_ item: BrewStoreBackgroundItem, enable: Bool) {
        Task.detached(priority: .userInitiated) {
            guard let plistURL = item.plistURL else { return }
            let uid = getuid()

            if enable {
                _ = BrewStoreCommandExecutor.shared.run(
                    executablePath: "/bin/launchctl",
                    arguments: ["bootstrap", "gui/\(uid)", plistURL.path],
                    timeout: 5
                )
            } else {
                _ = BrewStoreCommandExecutor.shared.run(
                    executablePath: "/bin/launchctl",
                    arguments: ["bootout", "gui/\(uid)/\(item.label)"],
                    timeout: 5
                )
            }

            await MainActor.run { [weak self] in
                self?.scanBackgroundItems()
            }
        }
    }

    func trashItem(_ item: BrewStoreBackgroundItem) {
        guard let plistURL = item.plistURL else { return }

        Task.detached(priority: .userInitiated) {
            // Unload from launchctl first
            let uid = getuid()
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: "/bin/launchctl",
                arguments: ["bootout", "gui/\(uid)/\(item.label)"],
                timeout: 5
            )

            let home = FileManager.default.homeDirectoryForCurrentUser
            let allowedRoots = [
                home.appendingPathComponent("Library/LaunchAgents"),
                URL(fileURLWithPath: "/Library/LaunchAgents")
            ]
            let validator = BrewStorePathSafetyValidator(allowedRoots: allowedRoots)
            let executor = BrewStoreTrashExecutor(validator: validator)

            let identity = BrewStoreAppIdentity(
                name: item.displayName,
                bundleIdentifier: item.label,
                applicationURL: plistURL
            )
            let plan = BrewStoreRemovalPlan(
                application: identity,
                candidates: [
                    BrewStoreRemovalCandidate(
                        url: plistURL,
                        kind: .helperTool,
                        size: 0,
                        confidence: .exactBundleIdentifier,
                        isSelected: true
                    )
                ]
            )
            _ = executor.execute(plan: plan)

            await MainActor.run { [weak self] in
                self?.statusMessage = "Moved \(item.displayName) to Trash."
                self?.scanBackgroundItems()
            }
        }
    }

    nonisolated static func fetchLoadedLaunchctlMap() -> [String: (pid: Int?, isLoaded: Bool)] {
        let result = BrewStoreCommandExecutor.shared.run(
            executablePath: "/bin/launchctl",
            arguments: ["list"],
            timeout: 5
        )
        guard result.succeeded else { return [:] }

        var map: [String: (pid: Int?, isLoaded: Bool)] = [:]
        let lines = result.standardOutput.components(separatedBy: .newlines)
        for line in lines {
            let tokens = line.split(separator: "\t").map(String.init)
            guard tokens.count >= 3 else { continue }
            let pidStr = tokens[0].trimmingCharacters(in: .whitespaces)
            let label = tokens[2].trimmingCharacters(in: .whitespaces)
            let pid = Int(pidStr)
            map[label] = (pid: pid, isLoaded: true)
        }
        return map
    }

    nonisolated static func scanAgentsDirectory(
        _ dir: URL,
        kind: BackgroundItemKind,
        loadedMap: [String: (pid: Int?, isLoaded: Bool)]
    ) -> [BrewStoreBackgroundItem] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        var items: [BrewStoreBackgroundItem] = []
        for file in files where file.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: file),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }

            let label = (plist["Label"] as? String) ?? file.deletingPathExtension().lastPathComponent
            let runAtLoad = (plist["RunAtLoad"] as? Bool) ?? false

            var programPath: String?
            if let prog = plist["Program"] as? String {
                programPath = prog
            } else if let args = plist["ProgramArguments"] as? [String], let first = args.first {
                programPath = first
            }

            let loadedInfo = loadedMap[label]
            let isLoaded = loadedInfo?.isLoaded ?? false
            let pid = loadedInfo?.pid
            let isRunning = pid != nil && pid! > 0

            let appName = deduceAppName(from: label, programPath: programPath)
            let friendlyName = deduceFriendlyName(from: label, appName: appName, filename: file.lastPathComponent)

            items.append(BrewStoreBackgroundItem(
                id: "\(kind.rawValue):\(label)",
                name: friendlyName,
                label: label,
                programPath: programPath,
                plistURL: file,
                kind: kind,
                associatedAppName: appName,
                isLoaded: isLoaded,
                isRunning: isRunning,
                runAtLoad: runAtLoad,
                pid: pid
            ))
        }
        return items
    }

    nonisolated static func fetchLoginItems() -> [BrewStoreBackgroundItem] {
        let script = "tell application \"System Events\" to get name of every login item"
        let result = BrewStoreCommandExecutor.shared.run(
            executablePath: "/usr/bin/osascript",
            arguments: ["-e", script],
            timeout: 5
        )
        guard result.succeeded else { return [] }

        let names = result.standardOutput
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return names.map { name in
            BrewStoreBackgroundItem(
                id: "loginitem:\(name)",
                name: name,
                label: name,
                programPath: nil,
                plistURL: nil,
                kind: .loginItem,
                associatedAppName: name,
                isLoaded: true,
                isRunning: true,
                runAtLoad: true,
                pid: nil
            )
        }
    }

    nonisolated static func deduceAppName(from label: String, programPath: String?) -> String? {
        if let path = programPath, path.contains(".app") {
            let parts = path.components(separatedBy: ".app")
            if let first = parts.first {
                return (first as NSString).lastPathComponent
            }
        }

        let clean = label.lowercased()
        if clean.contains("google") {
            return "Google Chrome / Keystone"
        }
        if clean.contains("docker") {
            return "Docker Desktop"
        }
        if clean.contains("spotify") {
            return "Spotify"
        }
        if clean.contains("slack") {
            return "Slack"
        }
        if clean.contains("dropbox") {
            return "Dropbox"
        }
        if clean.contains("microsoft") {
            return "Microsoft"
        }
        if clean.contains("adobe") {
            return "Adobe"
        }
        if clean.contains("zoom") {
            return "Zoom"
        }
        if clean.contains("raycast") {
            return "Raycast"
        }
        if clean.contains("alfred") {
            return "Alfred"
        }
        if clean.contains("tailscale") {
            return "Tailscale"
        }
        if clean.contains("steam") {
            return "Steam"
        }
        if clean.contains("brewstore") {
            return "BrewStore"
        }

        return nil
    }

    nonisolated static func deduceFriendlyName(from label: String, appName: String?, filename: String) -> String {
        if let app = appName {
            let lastToken = label.components(separatedBy: ".").last ?? ""
            if !lastToken.isEmpty, lastToken != label {
                return "\(app) (\(lastToken.capitalized))"
            }
            return app
        }
        let base = filename.replacingOccurrences(of: ".plist", with: "")
        let components = base.components(separatedBy: ".")
        if let last = components.last, components.count > 1 {
            return last.capitalized
        }
        return base
    }
}
