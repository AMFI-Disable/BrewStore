import AppKit
import Combine
import Foundation

/// Defines uninstallation strategies when removing or replacing applications.
enum BrewStoreAppUninstallMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case preserveData
    case purgeAllData
    case keepExisting

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .preserveData:
            "Keep App Data & Settings"
        case .purgeAllData:
            "Delete App and All Data"
        case .keepExisting:
            "Keep Existing App"
        }
    }

    var shortLabel: String {
        switch self {
        case .preserveData:
            "Delete app only"
        case .purgeAllData:
            "Clean uninstall"
        case .keepExisting:
            "Install alongside"
        }
    }

    var subtitle: String {
        switch self {
        case .preserveData:
            "Removes the app from Applications, but preserves your settings and preferences."
        case .purgeAllData:
            "Removes the app along with all its leftover caches, support files, and preferences."
        case .keepExisting:
            "Keeps your existing app and installs the open-source version side by side."
        }
    }

    var icon: String {
        switch self {
        case .preserveData:
            "app.badge.checkmark"
        case .purgeAllData:
            "sparkles.rectangle.stack.fill"
        case .keepExisting:
            "plus.rectangle.on.rectangle"
        }
    }
}

/// Manages integration with the Mole (`mo` / `mole`) macOS cleanup and uninstallation CLI.
@MainActor
final class BrewStoreMoleManager: ObservableObject {
    static let shared = BrewStoreMoleManager()

    @Published var isAvailable: Bool = false
    @Published var binaryPath: String?
    @Published var isOperating: Bool = false
    @Published var lastOutput: String?
    @Published var lastError: String?

    init() {
        detectBinary()
    }

    /// Scans standard locations and PATH for the `mo` or `mole` executable.
    func detectBinary() {
        let candidates = [
            "/opt/homebrew/bin/mo",
            "/opt/homebrew/bin/mole",
            "/usr/local/bin/mo",
            "/usr/local/bin/mole",
            "~/.local/bin/mo",
            "~/.local/bin/mole"
        ]

        let fileManager = FileManager.default
        for path in candidates {
            let expanded = NSString(string: path).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                self.binaryPath = expanded
                self.isAvailable = true
                return
            }
        }

        // Check PATH directories directly without running a subprocess
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            for binaryName in ["mo", "mole"] {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(binaryName).path
                if fileManager.isExecutableFile(atPath: candidate) {
                    self.binaryPath = candidate
                    self.isAvailable = true
                    return
                }
            }
        }

        self.binaryPath = nil
        self.isAvailable = false
    }

    /// Triggers installation of the `mole` formula via Homebrew.
    func installMole(manager: HomebrewManager) {
        let pkg = manager.packages.first(where: { $0.id == "mole" }) ?? BrewStorePackage(
            id: "mole",
            name: "Mole",
            description: "Deep clean and optimize your Mac CLI",
            homepage: "https://mole.fit",
            version: "1.53.0",
            kind: .formula
        )
        manager.perform(package: pkg, action: .install) { [weak self] _ in
            Task { @MainActor in
                self?.detectBinary()
            }
        }
    }

    /// Uninstalls an application using Mole (`mo uninstall`), removing all leftover caches and data.
    func uninstallAppWithMole(
        appName: String,
        permanent: Bool = false
    ) async -> (success: Bool, output: String) {
        if BrewStoreFixtureMode.isEnabled {
            let msg = "[Fixture] Simulated 'mo uninstall \(appName)' successfully purged all application data."
            self.lastOutput = msg
            return (true, msg)
        }

        guard isAvailable, let binary = binaryPath else {
            detectBinary()
            guard isAvailable, let binary = binaryPath else {
                let err = "Mole ('mo') binary not found. Please install Mole via Homebrew first."
                self.lastError = err
                return (false, err)
            }
            return await runMoleUninstall(binary: binary, appName: appName, permanent: permanent)
        }

        return await runMoleUninstall(binary: binary, appName: appName, permanent: permanent)
    }

    private func runMoleUninstall(
        binary: String,
        appName: String,
        permanent: Bool
    ) async -> (success: Bool, output: String) {
        self.isOperating = true
        defer { self.isOperating = false }

        return await Task.detached(priority: .userInitiated) { () -> (Bool, String) in
            let process = Process()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.executableURL = URL(fileURLWithPath: "/bin/bash")

            let permFlag = permanent ? "--permanent " : ""
            let escapedName = appName.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "printf 'y\\n\\n' | '\(binary)' uninstall \(permFlag)\"\(escapedName)\""
            process.arguments = ["-c", script]

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let success = process.terminationStatus == 0

                return (success, output)
            } catch {
                return (false, error.localizedDescription)
            }
        }.value
    }

    /// Moves only the .app bundle to macOS Trash, preserving all caches, Application Support, and preferences.
    func deleteBundleOnly(appURL: URL) throws {
        guard appURL.pathExtension == "app" || appURL.hasDirectoryPath else {
            throw NSError(
                domain: "com.amfi-disable.brewstore.mole",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid application bundle path: \(appURL.path)"]
            )
        }

        if BrewStoreFixtureMode.isEnabled {
            return
        }

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw NSError(
                domain: "com.amfi-disable.brewstore.mole",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Application does not exist at path: \(appURL.path)"]
            )
        }

        try FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
    }
}
