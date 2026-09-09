import AppKit
import Foundation
import SwiftUI

/// Identifies the package manager or distribution source of an application.
enum AppSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case homebrewCask = "cask"
    case homebrewFormula = "formula"
    case macAppStore = "mas"
    case unmanagedStandalone = "unmanaged"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .homebrewCask: "Homebrew Cask"
        case .homebrewFormula: "CLI Tool"
        case .macAppStore: "Mac App Store"
        case .unmanagedStandalone: "Standalone"
        }
    }

    var icon: String {
        switch self {
        case .homebrewCask: "shippingbox.fill"
        case .homebrewFormula: "terminal.fill"
        case .macAppStore: "apple.logo"
        case .unmanagedStandalone: "macwindow"
        }
    }

    var badgeColor: Color {
        switch self {
        case .homebrewCask: .green
        case .homebrewFormula: .blue
        case .macAppStore: .purple
        case .unmanagedStandalone: .orange
        }
    }
}

/// Represents an item in the unified software inventory regardless of installation source.
struct UnifiedAppItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleID: String?
    let installedVersion: String
    let latestVersion: String?
    let source: AppSource
    let appPath: String?
    let matchedCask: BrewStorePackage?
    let masApp: MASApp?
    let isDualAvailable: Bool
    let isOutdated: Bool

    var displayVersion: String {
        if isOutdated, let latest = latestVersion, !latest.isEmpty {
            return "\(installedVersion) → \(latest)"
        }
        return installedVersion
    }
}

/// Central manager orchestrating the complete Mac software inventory across Homebrew, Mac App Store, and standalone apps.
@MainActor
final class BrewStoreUnifiedAppManager: ObservableObject {
    static let shared = BrewStoreUnifiedAppManager()

    @Published var unifiedApps: [UnifiedAppItem] = []
    @Published var isRefreshing: Bool = false
    @Published var statusMessage: String = ""

    private let masManager = BrewStoreMASManager.shared
    private let adoptionManager = BrewStoreAppAdoptionManager.shared
    private let preferences = BrewStorePreferences.shared

    var casks: [UnifiedAppItem] {
        unifiedApps.filter { $0.source == .homebrewCask }
    }

    var formulae: [UnifiedAppItem] {
        unifiedApps.filter { $0.source == .homebrewFormula }
    }

    var masApps: [UnifiedAppItem] {
        unifiedApps.filter { $0.source == .macAppStore }
    }

    var unmanagedApps: [UnifiedAppItem] {
        unifiedApps.filter { $0.source == .unmanagedStandalone }
    }

    var outdatedApps: [UnifiedAppItem] {
        unifiedApps.filter(\.isOutdated)
    }

    var dualAvailableApps: [UnifiedAppItem] {
        unifiedApps.filter(\.isDualAvailable)
    }

    var totalOutdatedCount: Int {
        outdatedApps.count
    }

    /// Builds a unified list of all installed software from Homebrew, Mac App Store, and external apps.
    func rebuildInventory(homebrewManager: HomebrewManager) {
        var items: [UnifiedAppItem] = []
        var seenNames = Set<String>()
        var seenBundleIDs = Set<String>()

        // 1. Homebrew Installed Casks
        for pkg in homebrewManager.packages where pkg.kind == .cask && pkg.isInstalled {
            let installedVer = pkg.installedVersion ?? pkg.version
            let latestVer = pkg.isOutdated ? pkg.version : nil
            let item = UnifiedAppItem(
                id: "cask-\(pkg.id)",
                name: pkg.name,
                bundleID: nil,
                installedVersion: installedVer,
                latestVersion: latestVer,
                source: .homebrewCask,
                appPath: nil,
                matchedCask: pkg,
                masApp: nil,
                isDualAvailable: false,
                isOutdated: pkg.isOutdated
            )
            items.append(item)
            seenNames.insert(pkg.name.lowercased())
            for appName in pkg.applicationNames {
                seenNames.insert(appName.lowercased().replacingOccurrences(of: ".app", with: ""))
            }
        }

        // 2. Homebrew Installed Formulae (CLI tools)
        for pkg in homebrewManager.packages where pkg.kind == .formula && pkg.isInstalled {
            let installedVer = pkg.installedVersion ?? pkg.version
            let latestVer = pkg.isOutdated ? pkg.version : nil
            let item = UnifiedAppItem(
                id: "formula-\(pkg.id)",
                name: pkg.name,
                bundleID: nil,
                installedVersion: installedVer,
                latestVersion: latestVer,
                source: .homebrewFormula,
                appPath: nil,
                matchedCask: nil,
                masApp: nil,
                isDualAvailable: false,
                isOutdated: pkg.isOutdated
            )
            items.append(item)
        }

        // 3. Mac App Store Apps
        for mas in masManager.installedApps {
            let lowerName = mas.name.lowercased()
            let matchedCask = homebrewManager.packages.first { pkg in
                pkg.kind == .cask && (
                    pkg.name.localizedCaseInsensitiveCompare(mas.name) == .orderedSame ||
                        pkg.applicationNames.contains { $0.localizedCaseInsensitiveCompare("\(mas.name).app") == .orderedSame }
                )
            }
            let isDual = matchedCask != nil

            let item = UnifiedAppItem(
                id: "mas-\(mas.id)",
                name: mas.name,
                bundleID: nil,
                installedVersion: mas.installedVersion,
                latestVersion: mas.latestVersion,
                source: .macAppStore,
                appPath: nil,
                matchedCask: matchedCask,
                masApp: mas,
                isDualAvailable: isDual,
                isOutdated: mas.isOutdated
            )
            items.append(item)
            seenNames.insert(lowerName)
        }

        // 4. Standalone / Unmanaged Apps (discovered outside Homebrew and MAS)
        for scanned in adoptionManager.scannedApps where !scanned.isAlreadyManaged {
            let lowerName = scanned.appName.lowercased()
            if let bid = scanned.bundleID?.lowercased(), !bid.isEmpty {
                if seenBundleIDs.contains(bid) {
                    continue
                }
                seenBundleIDs.insert(bid)
            }
            if seenNames.contains(lowerName) {
                continue
            }

            let source: AppSource = scanned.isFromMacAppStore ? .macAppStore : .unmanagedStandalone
            let item = UnifiedAppItem(
                id: "scanned-\(scanned.id)",
                name: scanned.appName,
                bundleID: scanned.bundleID,
                installedVersion: scanned.installedVersion ?? "Unknown",
                latestVersion: nil,
                source: source,
                appPath: scanned.appPath,
                matchedCask: scanned.matchedCask,
                masApp: nil,
                isDualAvailable: scanned.isDualAvailable,
                isOutdated: false
            )
            items.append(item)
            seenNames.insert(lowerName)
        }

        // Sort: Outdated first, then by name ascending
        self.unifiedApps = items.sorted { a, b in
            if a.isOutdated != b.isOutdated {
                return a.isOutdated && !b.isOutdated
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Global 1-Click Update action updating both Homebrew packages and Mac App Store apps in coordination.
    func upgradeAllSoftware(homebrewManager: HomebrewManager) {
        statusMessage = "Upgrading all Mac software…"

        // 1. Upgrade Homebrew Packages
        homebrewManager.upgradeAllPackages()

        // 2. Upgrade Mac App Store apps if mas is available and outdated apps exist
        if masManager.isMASInstalled, !masManager.outdatedApps.isEmpty {
            masManager.upgradeAll()
        }
    }
}
