import AppKit
import Foundation

struct MASApp: Identifiable, Hashable, Codable {
    let id: String // App Store numerical ID
    let name: String
    let installedVersion: String
    var latestVersion: String?
    var isOutdated: Bool {
        latestVersion != nil && latestVersion != installedVersion
    }
}

@MainActor
final class BrewStoreMASManager: ObservableObject {
    static let shared = BrewStoreMASManager()

    @Published var isMASInstalled: Bool = false
    @Published var masBinaryPath: String?
    @Published var installedApps: [MASApp] = []
    @Published var isRefreshing: Bool = false
    @Published var isOperating: Bool = false
    @Published var statusMessage: String = ""

    var outdatedApps: [MASApp] {
        installedApps.filter(\.isOutdated)
    }

    init() {
        checkMASAvailability()
    }

    func checkMASAvailability() {
        let candidates = [
            "/opt/homebrew/bin/mas",
            "/usr/local/bin/mas",
            "/usr/bin/mas"
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            isMASInstalled = true
            masBinaryPath = found
        } else {
            isMASInstalled = false
            masBinaryPath = nil
        }
    }

    func installMAS(manager: HomebrewManager) {
        let masPkg = BrewStorePackage(
            id: "mas",
            name: "mas",
            description: "Mac App Store command-line interface",
            homepage: "https://github.com/mas-cli/mas",
            version: "latest",
            kind: .formula
        )
        manager.perform(package: masPkg, action: .install) { [weak self] success in
            if success {
                self?.checkMASAvailability()
                self?.refresh()
            }
        }
    }

    func refresh() {
        checkMASAvailability()
        isRefreshing = true

        if !isMASInstalled || masBinaryPath == nil {
            statusMessage = "Scanning installed Mac App Store receipts…"
            Task.detached(priority: .userInitiated) {
                let records = MASReceiptScanner.scanInstalledAppStoreApps()
                let apps = records.map {
                    MASApp(id: $0.id, name: $0.name, installedVersion: $0.installedVersion, latestVersion: nil)
                }
                await MainActor.run { [weak self] in
                    self?.installedApps = apps
                    self?.isRefreshing = false
                    self?.statusMessage = "Discovered \(apps.count) Mac App Store app(s) via native receipts. Install mas CLI to manage updates."
                }
            }
            return
        }

        guard let binPath = masBinaryPath else {
            isRefreshing = false
            return
        }

        statusMessage = "Checking Mac App Store applications…"

        Task.detached(priority: .userInitiated) {
            // 1. Fetch Installed
            let listResult = BrewStoreCommandExecutor.shared.run(
                executablePath: binPath,
                arguments: ["list"],
                timeout: 30,
                category: .readOnly
            )
            let listOutput = listResult.standardOutput

            // 2. Fetch Outdated
            let outResult = BrewStoreCommandExecutor.shared.run(
                executablePath: binPath,
                arguments: ["outdated"],
                timeout: 30,
                category: .readOnly
            )
            let outOutput = outResult.standardOutput

            var apps = Self.parseMASApps(listOutput: listOutput, outdatedOutput: outOutput)
            if apps.isEmpty {
                // Fallback to native receipt scanner if mas list produced nothing or failed
                let records = MASReceiptScanner.scanInstalledAppStoreApps()
                apps = records.map {
                    MASApp(id: $0.id, name: $0.name, installedVersion: $0.installedVersion, latestVersion: nil)
                }
            }

            let finalApps = apps
            await MainActor.run { [weak self] in
                self?.installedApps = finalApps
                self?.isRefreshing = false
                self?.statusMessage = "Mac App Store apps updated (\(finalApps.count) found)."
            }
        }
    }

    func upgradeApp(_ app: MASApp) {
        guard let binPath = masBinaryPath, !isOperating else { return }
        isOperating = true
        statusMessage = "Upgrading \(app.name) via Mac App Store…"

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                BrewStoreCommandExecutor.shared.run(
                    executablePath: binPath,
                    arguments: ["upgrade", app.id],
                    timeout: 300,
                    category: .reversibleMutation
                )
            }.value

            self?.isOperating = false
            if result.succeeded {
                self?.statusMessage = "Upgraded \(app.name)."
            } else {
                let err = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.statusMessage = "Failed to upgrade \(app.name)\(err.isEmpty ? "" : ": \(err)")."
            }
            self?.refresh()
        }
    }

    func installApp(id: String, name: String = "") {
        guard let binPath = masBinaryPath, !isOperating else { return }
        isOperating = true
        statusMessage = name.isEmpty ? "Installing App Store app #\(id)…" : "Installing \(name) via Mac App Store…"

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                BrewStoreCommandExecutor.shared.run(
                    executablePath: binPath,
                    arguments: ["install", id],
                    timeout: 600,
                    category: .reversibleMutation
                )
            }.value

            self?.isOperating = false
            if result.succeeded {
                self?.statusMessage = name.isEmpty ? "Installed app #\(id)." : "Installed \(name)."
            } else {
                let err = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = name.isEmpty ? "app #\(id)" : name
                self?.statusMessage = "Failed to install \(title)\(err.isEmpty ? "" : ": \(err)")."
            }
            self?.refresh()
        }
    }

    func upgradeAll() {
        guard let binPath = masBinaryPath, !isOperating else { return }
        isOperating = true
        statusMessage = "Upgrading all Mac App Store apps…"

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                BrewStoreCommandExecutor.shared.run(
                    executablePath: binPath,
                    arguments: ["upgrade"],
                    timeout: 600,
                    category: .reversibleMutation
                )
            }.value

            self?.isOperating = false
            if result.succeeded {
                self?.statusMessage = "Completed Mac App Store upgrades."
            } else {
                let err = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.statusMessage = "Failed Mac App Store upgrades\(err.isEmpty ? "" : ": \(err)")."
            }
            self?.refresh()
        }
    }

    nonisolated static func parseMASApps(listOutput: String, outdatedOutput: String) -> [MASApp] {
        var outdatedMap: [String: String] = [:] // id -> latestVersion
        for line in outdatedOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Format: 497799835 Xcode (15.3 -> 15.4)
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2, let id = parts.first {
                if let arrowIndex = parts.firstIndex(of: "->"), arrowIndex + 1 < parts.count {
                    let latest = parts[arrowIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                    outdatedMap[id] = latest
                }
            }
        }

        var apps: [MASApp] = []
        for line in listOutput.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Format: 497799835 Xcode (15.3)
            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard tokens.count >= 2, let id = tokens.first else { continue }

            var version = ""
            var nameTokens: [String] = []
            for token in tokens.dropFirst() {
                if token.hasPrefix("("), token.hasSuffix(")") {
                    version = token.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                } else {
                    nameTokens.append(token)
                }
            }

            let name = nameTokens.joined(separator: " ")
            let latest = outdatedMap[id]
            apps.append(MASApp(
                id: id,
                name: name.isEmpty ? "App \(id)" : name,
                installedVersion: version.isEmpty ? "Installed" : version,
                latestVersion: latest
            ))
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
