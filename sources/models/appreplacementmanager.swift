import AppKit
import Foundation

struct OpenSourceAlternativeMapping: Identifiable, Hashable, Codable {
    let id: String
    let targetProprietaryApp: String
    let targetBundleID: String?
    let replacementPackageID: String
    let replacementName: String
    let replacementKind: BrewPackageKind
    let category: String
    let advantages: [String]
    let whyReplace: String
}

@MainActor
final class BrewStoreAppReplacementManager: ObservableObject {
    static let shared = BrewStoreAppReplacementManager()

    /// Curated high quality mappings for external / commercial tools to modern Homebrew alternatives
    nonisolated static let curatedAlternativeCatalog: [OpenSourceAlternativeMapping] = [
        OpenSourceAlternativeMapping(
            id: "cleanmymac-mole",
            targetProprietaryApp: "CleanMyMac",
            targetBundleID: "com.macpaw.CleanMyMac4",
            replacementPackageID: "mole",
            replacementName: "Mole",
            replacementKind: .formula,
            category: "Deep Disk Cleaner & Optimizer",
            advantages: ["Fast macOS Cleanup", "Free & Open Source CLI", "Cleans Xcode, Caches, Logs, Trash & Docker"],
            whyReplace: "Mole is an open-source macOS cleanup utility designed to reclaim disk space (Xcode DerivedData, CocoaPods, Homebrew caches, app logs) without background processes."
        ),
        OpenSourceAlternativeMapping(
            id: "cleanmymac-pearcleaner",
            targetProprietaryApp: "CleanMyMac",
            targetBundleID: "com.macpaw.CleanMyMac4",
            replacementPackageID: "pearcleaner",
            replacementName: "Pearcleaner",
            replacementKind: .cask,
            category: "Cleaner & App Uninstaller",
            advantages: ["Free & Open Source", "Zero Telemetry", "Native Swift UI"],
            whyReplace: "Pearcleaner is a lightweight, privacy-focused open-source app uninstaller that thoroughly deletes leftover caches without subscriptions."
        ),
        OpenSourceAlternativeMapping(
            id: "docker-orbstack",
            targetProprietaryApp: "Docker Desktop",
            targetBundleID: "com.docker.docker",
            replacementPackageID: "orbstack",
            replacementName: "OrbStack",
            replacementKind: .cask,
            category: "Container & Linux VM Runtime",
            advantages: ["Fast Startup (<2s)", "Low CPU & Memory Overhead", "Drop-in Docker CLI Compatible"],
            whyReplace: "OrbStack runs Docker containers and Linux virtual machines natively with low resource usage and local domain networking."
        ),
        OpenSourceAlternativeMapping(
            id: "postman-bruno",
            targetProprietaryApp: "Postman",
            targetBundleID: "com.postmanlabs.mac",
            replacementPackageID: "bruno",
            replacementName: "Bruno",
            replacementKind: .cask,
            category: "API Client & Testing",
            advantages: ["Offline-First Plain Text Collections", "Git Version Control Friendly", "No Mandatory Cloud Login"],
            whyReplace: "Bruno stores your API collections directly in local Git repositories as plain text, eliminating forced cloud sync and privacy risks."
        ),
        OpenSourceAlternativeMapping(
            id: "tableplus-dbeaver",
            targetProprietaryApp: "TablePlus",
            targetBundleID: "com.tinyapp.TablePlus",
            replacementPackageID: "dbeaver-community",
            replacementName: "DBeaver Community",
            replacementKind: .cask,
            category: "Database GUI Client",
            advantages: ["Universal DB Support (Postgres, MySQL, SQLite, Redis)", "Unlimited Tabs & Connections", "Open-Source Community Edition"],
            whyReplace: "DBeaver supports over 80 database engines with unlimited workspace tabs, SQL autocompletion, and schema diagrams without paid license limits."
        ),
        OpenSourceAlternativeMapping(
            id: "magnet-rectangle",
            targetProprietaryApp: "Magnet",
            targetBundleID: "com.crowdcafe.windowmagnet",
            replacementPackageID: "rectangle",
            replacementName: "Rectangle",
            replacementKind: .cask,
            category: "Window Snapping & Management",
            advantages: ["100% Free & Open Source", "Customizable Keyboard Hotkeys", "Snap Zones & Multi-Monitor Support"],
            whyReplace: "Rectangle is the gold-standard open-source window manager with advanced keyboard shortcuts, edge snapping, and zero tracking."
        ),
        OpenSourceAlternativeMapping(
            id: "sublime-zed",
            targetProprietaryApp: "Sublime Text",
            targetBundleID: "com.sublimetext.4",
            replacementPackageID: "zed",
            replacementName: "Zed Editor",
            replacementKind: .cask,
            category: "High-Performance Code Editor",
            advantages: ["GPU-Accelerated 120 FPS Rendering", "Rust Multi-Threaded Architecture", "Built-in AI Assistant & Collaboration"],
            whyReplace: "Zed is an open-source, ultra-fast code editor engineered in Rust with instantaneous keystroke latency and built-in Language Server Protocol (LSP)."
        ),
        OpenSourceAlternativeMapping(
            id: "onepassword-bitwarden",
            targetProprietaryApp: "1Password",
            targetBundleID: "com.1password.1password",
            replacementPackageID: "bitwarden",
            replacementName: "Bitwarden",
            replacementKind: .cask,
            category: "Password & Secrets Manager",
            advantages: ["Open-Source End-to-End Encryption", "Cross-Platform Auto-Fill", "Self-Hostable or Free Cloud Vault"],
            whyReplace: "Bitwarden provides audited zero-knowledge encryption, secure biometric unlocking, and free synchronization across all your devices."
        ),
        OpenSourceAlternativeMapping(
            id: "amphetamine-keepingyouawake",
            targetProprietaryApp: "Amphetamine",
            targetBundleID: "com.if.Amphetamine",
            replacementPackageID: "keepingyouawake",
            replacementName: "KeepingYouAwake",
            replacementKind: .cask,
            category: "Sleep Prevention Utility",
            advantages: ["Lightweight Menu Bar App", "Modern macOS Caffeinate Wrapper", "Zero Permissions Overhead"],
            whyReplace: "KeepingYouAwake is a minimalist, open-source clone of Caffeine using Apple's native caffeinate utility under the hood."
        ),
        OpenSourceAlternativeMapping(
            id: "iterm-ghostty",
            targetProprietaryApp: "iTerm2",
            targetBundleID: "com.googlecode.iterm2",
            replacementPackageID: "ghostty",
            replacementName: "Ghostty",
            replacementKind: .cask,
            category: "GPU Terminal Emulator",
            advantages: ["Native macOS Metal Rendering", "Ultra-Low Latency Typing", "Clean Typography & Shader Support"],
            whyReplace: "Ghostty brings modern GPU rendering, native macOS tabs and split panes, and extreme render performance compared to legacy terminal emulators."
        )
    ]

    @Published var detectedAlternatives: [OpenSourceAlternativeMapping] = []
    @Published var isScanning = false

    func scanForReplacements(scannedApps: [ScannedAppItem]) {
        isScanning = true

        let scannedNames = Set(scannedApps.map { $0.appName.lowercased() })
        let scannedBundleIDs = Set(scannedApps.compactMap { $0.bundleID?.lowercased() })

        var matches: [OpenSourceAlternativeMapping] = []
        for mapping in Self.curatedAlternativeCatalog {
            let matchesName = scannedNames.contains(where: { $0.contains(mapping.targetProprietaryApp.lowercased()) })
            let matchesBundle = mapping.targetBundleID.map { scannedBundleIDs.contains($0.lowercased()) } ?? false

            if matchesName || matchesBundle {
                matches.append(mapping)
            }
        }

        self.detectedAlternatives = matches
        self.isScanning = false
    }

    func findMatchingScannedApp(for mapping: OpenSourceAlternativeMapping, in apps: [ScannedAppItem]) -> ScannedAppItem? {
        if let bundleID = mapping.targetBundleID?.lowercased() {
            if let match = apps.first(where: { $0.bundleID?.lowercased() == bundleID }) {
                return match
            }
        }
        let targetName = mapping.targetProprietaryApp.lowercased()
        return apps.first(where: {
            let name = $0.appName.lowercased()
            return name == targetName || name.contains(targetName)
        })
    }

    func findAppBundleURL(for mapping: OpenSourceAlternativeMapping, scannedApps: [ScannedAppItem] = []) -> URL? {
        if let scanned = findMatchingScannedApp(for: mapping, in: scannedApps) {
            let url = URL(fileURLWithPath: scanned.appPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let appName = mapping.targetProprietaryApp
        let candidatePaths = [
            "/Applications/\(appName).app",
            "/Applications/\(appName) 4.app",
            "/Applications/\(appName) Desktop.app",
            NSString(string: "~/Applications/\(appName).app").expandingTildeInPath
        ]
        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Safely purges an application bundle and its associated caches/preferences using native macOS Foundation APIs.
    /// All items are moved to macOS Trash (~/.Trash) rather than permanently deleted.
    @discardableResult
    func purgeAllApplicationDataNatively(
        appName: String,
        bundleID: String?,
        appURL: URL?
    ) -> (success: Bool, movedCount: Int, errors: [String]) {
        if BrewStoreFixtureMode.isEnabled {
            return (true, 1, [])
        }

        var movedCount = 0
        var errors: [String] = []
        let fileManager = FileManager.default

        // 1. Move App Bundle to Trash
        let dummyMapping = OpenSourceAlternativeMapping(
            id: "",
            targetProprietaryApp: appName,
            targetBundleID: bundleID,
            replacementPackageID: "",
            replacementName: "",
            replacementKind: .formula,
            category: "",
            advantages: [],
            whyReplace: ""
        )
        if let bundle = appURL ?? findAppBundleURL(for: dummyMapping) {
            if fileManager.fileExists(atPath: bundle.path) {
                do {
                    try fileManager.trashItem(at: bundle, resultingItemURL: nil)
                    movedCount += 1
                } catch {
                    errors.append("Failed to trash app bundle: \(error.localizedDescription)")
                }
            }
        }

        // 2. Scan and Trash Residual Application Support, Caches, Preferences
        let libraryURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)

        var candidatePaths: [URL] = []
        let searchNames = [appName, bundleID].compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        for name in searchNames {
            candidatePaths.append(libraryURL.appendingPathComponent("Application Support").appendingPathComponent(name))
            candidatePaths.append(libraryURL.appendingPathComponent("Caches").appendingPathComponent(name))
            candidatePaths.append(libraryURL.appendingPathComponent("Preferences").appendingPathComponent("\(name).plist"))
            candidatePaths.append(libraryURL.appendingPathComponent("Saved Application State").appendingPathComponent("\(name).savedState"))
            candidatePaths.append(libraryURL.appendingPathComponent("HTTPStorages").appendingPathComponent(name))
            candidatePaths.append(libraryURL.appendingPathComponent("WebKit").appendingPathComponent(name))
            candidatePaths.append(libraryURL.appendingPathComponent("Containers").appendingPathComponent(name))
        }

        let safetyValidator = BrewStorePathSafetyValidator(allowedRoots: [libraryURL])

        for target in candidatePaths {
            guard fileManager.fileExists(atPath: target.path) else { continue }
            do {
                try safetyValidator.validate(target, fileManager: fileManager)
                try fileManager.trashItem(at: target, resultingItemURL: nil)
                movedCount += 1
            } catch {
                errors.append("Failed to trash \(target.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return (errors.isEmpty || movedCount > 0, movedCount, errors)
    }

    func executeReplacement(
        mapping: OpenSourceAlternativeMapping,
        mode: BrewStoreAppUninstallMode,
        appURL: URL?,
        manager: HomebrewManager
    ) async -> (success: Bool, message: String) {
        switch mode {
        case .preserveData:
            if let url = appURL ?? findAppBundleURL(for: mapping) {
                do {
                    try BrewStoreMoleManager.shared.deleteBundleOnly(appURL: url)
                } catch {
                    return (false, "Failed to remove application bundle: \(error.localizedDescription)")
                }
            }
        case .purgeAllData:
            let appName = mapping.targetProprietaryApp
            if BrewStoreMoleManager.shared.isAvailable {
                let (success, output) = await BrewStoreMoleManager.shared.uninstallAppWithMole(appName: appName)
                if !success, !BrewStoreFixtureMode.isEnabled {
                    let nativeResult = purgeAllApplicationDataNatively(
                        appName: appName,
                        bundleID: mapping.targetBundleID,
                        appURL: appURL
                    )
                    if !nativeResult.success {
                        return (false, "Uninstallation failed: \(output)")
                    }
                }
            } else {
                let nativeResult = purgeAllApplicationDataNatively(
                    appName: appName,
                    bundleID: mapping.targetBundleID,
                    appURL: appURL
                )
                if !nativeResult.success, !BrewStoreFixtureMode.isEnabled {
                    return (false, "Native uninstallation failed: \(nativeResult.errors.joined(separator: ", "))")
                }
            }
        case .keepExisting:
            break
        }

        let pkg = manager.packages.first(where: { $0.id == mapping.replacementPackageID }) ?? BrewStorePackage(
            id: mapping.replacementPackageID,
            name: mapping.replacementName,
            description: mapping.whyReplace,
            homepage: "",
            version: "",
            kind: mapping.replacementKind
        )
        manager.perform(package: pkg, action: .install)

        return (true, "Replacement initiated successfully.")
    }

    func installReplacement(mapping: OpenSourceAlternativeMapping, manager: HomebrewManager) {
        let pkg = manager.packages.first(where: { $0.id == mapping.replacementPackageID }) ?? BrewStorePackage(
            id: mapping.replacementPackageID,
            name: mapping.replacementName,
            description: mapping.whyReplace,
            homepage: "",
            version: "",
            kind: mapping.replacementKind
        )
        manager.perform(package: pkg, action: .install)
    }
}
