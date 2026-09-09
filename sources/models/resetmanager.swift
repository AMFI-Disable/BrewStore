import AppKit
import Foundation
import SwiftUI

public enum BrewStoreResetTier: String, CaseIterable, Identifiable, Sendable {
    case safe = "App Data & Cache"
    case caution = "BrewStore Preferences"
    case danger = "Homebrew Maintenance & Links"
    case dangerDanger = "Uninstall All Software"

    public var id: String {
        rawValue
    }

    public var badgeColor: Color {
        switch self {
        case .safe: .blue
        case .caution: .yellow
        case .danger: .orange
        case .dangerDanger: .red
        }
    }

    public var icon: String {
        switch self {
        case .safe: "folder.badge.gearshape"
        case .caution: "slider.horizontal.3"
        case .danger: "wrench.and.screwdriver"
        case .dangerDanger: "trash.fill"
        }
    }
}

public enum BrewStoreResetOption: String, CaseIterable, Identifiable, Sendable {
    // Tier 1: App Data & Cache
    case unpinEverything = "Unpin All Packages"
    case unstarEverything = "Clear Wishlist & Bookmarks"

    // Tier 2: BrewStore Preferences
    case clearPersonalSettings = "Reset App Preferences"
    case resetEverythingForApp = "Restore Factory Settings"

    // Tier 3: Homebrew Maintenance & Links
    case cleanupEverything = "Clean Cache & Old Versions"
    case unlinkEverything = "Unlink All CLI Binaries"
    case untapEverything = "Remove Third-Party Taps"

    /// Tier 4: Uninstall All Software
    case uninstallEverything = "Uninstall All Packages"

    public var id: String {
        rawValue
    }

    public var shortActionTitle: String {
        switch self {
        case .unpinEverything: "Unpin All"
        case .unstarEverything: "Clear Wishlist"
        case .clearPersonalSettings: "Reset Preferences"
        case .resetEverythingForApp: "Restore Defaults"
        case .cleanupEverything: "Clean Cache"
        case .unlinkEverything: "Unlink Binaries"
        case .untapEverything: "Remove Taps"
        case .uninstallEverything: "Uninstall All"
        }
    }

    public var tier: BrewStoreResetTier {
        switch self {
        case .unpinEverything, .unstarEverything:
            .safe
        case .clearPersonalSettings, .resetEverythingForApp:
            .caution
        case .cleanupEverything, .unlinkEverything, .untapEverything:
            .danger
        case .uninstallEverything:
            .dangerDanger
        }
    }

    public var icon: String {
        switch self {
        case .unpinEverything: "pin.slash.fill"
        case .unstarEverything: "star.slash.fill"
        case .cleanupEverything: "sparkles"
        case .clearPersonalSettings: "slider.horizontal.3"
        case .resetEverythingForApp: "arrow.counterclockwise.circle.fill"
        case .unlinkEverything: "link.badge.plus"
        case .untapEverything: "shippingbox.and.arrow.backward.fill"
        case .uninstallEverything: "trash.fill"
        }
    }

    public var outcomeTitle: String {
        switch self {
        case .unpinEverything: "Unlock Package Upgrades"
        case .unstarEverything: "Clear Saved Wishlist & Bookmarks"
        case .clearPersonalSettings: "Reset Preferences to Defaults"
        case .resetEverythingForApp: "Restore App to Initial State"
        case .cleanupEverything: "Clear Temporary Download Cache"
        case .unlinkEverything: "Unlink Command-Line Tools from PATH"
        case .untapEverything: "Remove Third-Party Package Sources"
        case .uninstallEverything: "Remove All Installed Packages"
        }
    }

    public var consequenceBadge: String {
        switch self {
        case .unpinEverything: "Allows upgrades • Keeps installed software"
        case .unstarEverything: "Clears bookmarks • Keeps packages on disk"
        case .clearPersonalSettings: "Resets UI settings • Leaves packages intact"
        case .resetEverythingForApp: "Clears app cache • Leaves installed packages untouched"
        case .cleanupEverything: "Frees disk space • Keeps current active versions"
        case .unlinkEverything: "Commands temporarily hidden in PATH • Keeps files in Cellar"
        case .untapEverything: "Removes custom sources • Keeps installed software"
        case .uninstallEverything: "High Impact • Deletes all packages & casks"
        }
    }

    public var description: String {
        switch self {
        case .unpinEverything:
            "Remove version locks from installed packages, allowing them to upgrade normally. Installed software is not removed."
        case .unstarEverything:
            "Clear all starred packages, bookmarks, and custom user collections. No packages are uninstalled."
        case .cleanupEverything:
            "Remove cached downloads, outdated archives, and stale lockfiles. Active packages remain installed."
        case .clearPersonalSettings:
            "Reset auto-refresh timers, dock badge lifecycle, notification preferences, themes, and window vibrancy back to default."
        case .resetEverythingForApp:
            "Restore BrewStore application defaults. Clears cache, wishlists, logs, and disconnects all Git accounts while keeping Homebrew software intact."
        case .unlinkEverything:
            "Unlink command-line tools from your shell search path while keeping all files safely in the Cellar."
        case .untapEverything:
            "Remove all third-party custom package repositories, leaving official Homebrew packages intact."
        case .uninstallEverything:
            "Completely uninstall and remove all Homebrew packages, formulae, and apps from your Mac to reclaim disk storage."
        }
    }
}

@MainActor
public final class BrewStoreResetManager: ObservableObject {
    public static let shared = BrewStoreResetManager()
    public static let nuclearVerificationPhrase = "UNINSTALL ALL PACKAGES"

    @Published public var isResetting: Bool = false
    @Published public var lastResetMessage: String?
    @Published public var showingResetSheet: Bool = false
    @Published public var isPerformingNuclearUninstall: Bool = false

    public init() {}

    // MARK: - Category 1: BrewStore Local Data

    func unpinEverything(manager: HomebrewManager) {
        BrewStorePackagePinningManager.shared.resetAllPins(manager: manager)
        lastResetMessage = "Unpinned all package version locks."
    }

    public func unstarEverything() {
        BrewStoreWishlistManager.shared.resetWishlistAndCollections()
        CommunityShowdownManager.shared.resetShowdown()
        lastResetMessage = "Cleared all wishlist stars and collections."
    }

    func cleanupEverything(manager: HomebrewManager) {
        BrewStoreFastCacheEngine.clearCache()
        if let prefix = manager.brewPrefix {
            _ = BrewStoreLockManager.shared.forceUnlock(prefix: prefix)
        }
        manager.clearOperationHistory()
        manager.resetState()
        manager.cleanup(dryRun: false)
        lastResetMessage = "Cleaned up all caches, locks, logs, and pruned Homebrew storage."
    }

    // MARK: - Category 2: App Settings & Preferences

    public func clearPersonalSettings() {
        BrewStorePreferences.shared.resetToDefaults()
        BrewStoreLaunchAgentManager.shared.intervalHours = 1
        BrewStoreThemeVibrancyManager.shared.reset()
        BrewStoreLocalizationManager.shared.reset()
        NotificationCenter.default.post(name: .brewStoreAutoRefreshPreferencesDidChange, object: nil)
        NotificationCenter.default.post(name: .brewStoreDockLifecyclePreferenceDidChange, object: nil)
        lastResetMessage = "Personal settings and interface preferences restored to defaults."
    }

    public func restoreDefaultSettings() {
        clearPersonalSettings()
        lastResetMessage = "Default settings and interface preferences restored."
    }

    public func restoreOptimalDefaults() {
        restoreDefaultSettings()
    }

    public func resetPreferences() {
        clearPersonalSettings()
    }

    func resetDiscoveryCache(discovery: BrewStoreDiscoveryCatalog) {
        discovery.clearCache()
        discovery.load()
    }

    public func resetWishlist() {
        unstarEverything()
    }

    func resetPinnedPackages(manager: HomebrewManager) {
        unpinEverything(manager: manager)
    }

    func resetHistoryAndLogs(manager: HomebrewManager) {
        manager.clearOperationHistory()
        manager.resetState()
    }

    public func resetThemeAndAppearance() {
        BrewStoreThemeVibrancyManager.shared.reset()
        BrewStoreLocalizationManager.shared.reset()
    }

    func resetEverythingForApp(manager: HomebrewManager, discovery: BrewStoreDiscoveryCatalog) {
        isResetting = true
        clearPersonalSettings()
        unpinEverything(manager: manager)
        unstarEverything()
        cleanupEverything(manager: manager)
        discovery.clearCache()
        discovery.load()
        GitServiceManager.shared.disconnectAllAccounts()
        lastResetMessage = "BrewStore application environment has been restored to default settings."
        isResetting = false
    }

    func performFactoryReset(manager: HomebrewManager, discovery: BrewStoreDiscoveryCatalog) {
        resetEverythingForApp(manager: manager, discovery: discovery)
    }

    // MARK: - Category 3: Homebrew Cleanups & Changes

    func unlinkEverything(manager: HomebrewManager) {
        let linkedFormulae = manager.packages.filter { $0.kind == .formula && $0.isInstalled }
        guard !linkedFormulae.isEmpty else {
            lastResetMessage = "No installed formulae found to unlink."
            return
        }

        isResetting = true
        manager.batchPerform(packages: linkedFormulae, action: .unlink) { [weak self] _ in
            self?.lastResetMessage = "Unlinked \(linkedFormulae.count) formulae from Homebrew PATH."
            self?.isResetting = false
        }
    }

    func untapEverything(manager: HomebrewManager) {
        let thirdPartyTaps = manager.taps.filter {
            let name = $0.name.lowercased()
            return name != "homebrew/core" && name != "homebrew/cask"
        }

        guard !thirdPartyTaps.isEmpty else {
            lastResetMessage = "No third-party custom taps found to untap."
            return
        }

        isResetting = true
        for tap in thirdPartyTaps {
            manager.untap(name: tap.name)
        }
        lastResetMessage = "Untapped \(thirdPartyTaps.count) third-party custom taps."
        isResetting = false
    }

    // MARK: - Category 4: Complete Software Removal

    public func verifyNuclearPhrase(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines) == Self.nuclearVerificationPhrase
    }

    func uninstallEverything(manager: HomebrewManager) {
        let installedPackages = manager.packages.filter(\.isInstalled)
        guard !installedPackages.isEmpty else {
            lastResetMessage = "No installed packages found on this Mac."
            return
        }

        isPerformingNuclearUninstall = true
        isResetting = true

        // First uninstall casks, then formulae
        manager.batchPerform(packages: installedPackages, action: .uninstall) { [weak self] _ in
            manager.autoremove()
            manager.cleanup(dryRun: false)
            self?.lastResetMessage = "All \(installedPackages.count) Homebrew packages have been uninstalled."
            self?.isResetting = false
            self?.isPerformingNuclearUninstall = false
        }
    }

    // MARK: - Selective Reset Batch Runner

    func performSelectiveReset(
        options: Set<BrewStoreResetOption>,
        manager: HomebrewManager,
        discovery: BrewStoreDiscoveryCatalog
    ) {
        isResetting = true

        if options.contains(.unpinEverything) {
            unpinEverything(manager: manager)
        }
        if options.contains(.unstarEverything) {
            unstarEverything()
        }
        if options.contains(.cleanupEverything) {
            cleanupEverything(manager: manager)
        }
        if options.contains(.clearPersonalSettings) {
            clearPersonalSettings()
        }
        if options.contains(.resetEverythingForApp) {
            resetEverythingForApp(manager: manager, discovery: discovery)
        }
        if options.contains(.unlinkEverything) {
            unlinkEverything(manager: manager)
        }
        if options.contains(.untapEverything) {
            untapEverything(manager: manager)
        }
        if options.contains(.uninstallEverything) {
            uninstallEverything(manager: manager)
        }

        lastResetMessage = "Completed selected reset operations for \(options.count) module\(options.count == 1 ? "" : "s")."
        isResetting = false
    }
}
