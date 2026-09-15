import Foundation
import SwiftUI

/// Defines user preference for managing dual-available apps (Homebrew vs. Mac App Store).
enum AppSourcePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case homebrew = "homebrew"
    case macAppStore = "macAppStore"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .homebrew: "Homebrew Cask (Recommended)"
        case .macAppStore: "Mac App Store"
        }
    }

    var shortLabel: String {
        switch self {
        case .homebrew: "Homebrew"
        case .macAppStore: "App Store"
        }
    }

    var subtitle: String {
        switch self {
        case .homebrew: "Faster updates, CLI scriptable, and no Apple ID password prompts."
        case .macAppStore: "Managed via official Apple Mac App Store."
        }
    }
}

@MainActor
final class BrewStorePreferences: ObservableObject {
    static let shared = BrewStorePreferences()

    private let defaults = UserDefaults.standard

    /// Keys
    enum Keys {
        static let isAutoCheckEnabled = "pref_auto_check_enabled"
        static let checkIntervalHours = "pref_check_interval_hours"
        static let autoFetchMetadata = "pref_auto_fetch_metadata"
        static let autoCleanupOnQuit = "pref_auto_cleanup_on_quit"
        static let showNotifications = "pref_show_notifications"
        static let showMenuBarBadge = "pref_show_menubar_badge"
        static let menuBarBadgeStyle = "pref_menubar_badge_style"
        static let defaultMenuBarTab = "pref_default_menubar_tab"
        static let menuBarCloseOnAction = "pref_menubar_close_on_action"
        static let compactMenuBarView = "pref_menubar_compact_view"

        // Live Auto-Refresh
        static let isAutoRefreshEnabled = "pref_auto_refresh_enabled"
        static let autoRefreshIntervalSeconds = "pref_auto_refresh_interval_seconds"
        static let autoRefreshOnExternalBrewCommands = "pref_auto_refresh_external_commands"

        // Innovations & Feature Flags
        static let enableEditorialStories = "pref_enable_editorial_stories"
        static let enableDeveloperStacks = "pref_enable_developer_stacks"
        static let enableVisualDependencyGraph = "pref_enable_visual_dependency_graph"
        static let enableAppCleaner = "pref_enable_app_cleaner"
        static let enableAutoSnapshotBeforeMutations = "pref_enable_auto_snapshot_mutations"
        static let enableAutoGistCloudSync = "pref_enable_auto_gist_cloud_sync"
        static let showConsoleDrawer = "pref_show_console_drawer"
        static let hideDockIconWhenWindowClosed = "pref_hide_dock_icon_when_window_closed"
        static let confirmOperationsBeforeExecution = "pref_confirm_operations_before_execution"
        static let defaultUninstallMode = "pref_default_uninstall_mode"
        static let defaultAppSourcePreference = "pref_default_app_source_preference"

        // Decluttering & Hiding
        static let hideCompletedBundles = "pref_hide_completed_bundles"
        static let hideInstalledWishlist = "pref_hide_installed_wishlist"
        static let hideIdenticalSnapshots = "pref_hide_identical_snapshots"

        // Webhooks & Automation
        static let webhookURL = "pref_webhook_url"
        static let webhookEnabled = "pref_webhook_enabled"
        static let webhookNotifyOnUpdatesFound = "pref_webhook_notify_on_updates_found"
    }

    /// Webhooks & Automation Preferences
    @Published var webhookURL: String {
        didSet { defaults.set(webhookURL, forKey: Keys.webhookURL) }
    }

    @Published var webhookEnabled: Bool {
        didSet { defaults.set(webhookEnabled, forKey: Keys.webhookEnabled) }
    }

    @Published var webhookNotifyOnUpdatesFound: Bool {
        didSet { defaults.set(webhookNotifyOnUpdatesFound, forKey: Keys.webhookNotifyOnUpdatesFound) }
    }

    /// Decluttering & Hiding Preferences
    @Published var hideCompletedBundles: Bool {
        didSet { defaults.set(hideCompletedBundles, forKey: Keys.hideCompletedBundles) }
    }

    @Published var hideInstalledWishlist: Bool {
        didSet { defaults.set(hideInstalledWishlist, forKey: Keys.hideInstalledWishlist) }
    }

    @Published var hideIdenticalSnapshots: Bool {
        didSet { defaults.set(hideIdenticalSnapshots, forKey: Keys.hideIdenticalSnapshots) }
    }

    @Published var defaultAppSourcePreference: AppSourcePreference {
        didSet { defaults.set(defaultAppSourcePreference.rawValue, forKey: Keys.defaultAppSourcePreference) }
    }

    @Published var confirmOperationsBeforeExecution: Bool {
        didSet { defaults.set(confirmOperationsBeforeExecution, forKey: Keys.confirmOperationsBeforeExecution) }
    }

    @Published var hideDockIconWhenWindowClosed: Bool {
        didSet {
            defaults.set(hideDockIconWhenWindowClosed, forKey: Keys.hideDockIconWhenWindowClosed)
            NotificationCenter.default.post(name: .brewStoreDockLifecyclePreferenceDidChange, object: nil)
        }
    }

    @Published var showConsoleDrawer: Bool {
        didSet { defaults.set(showConsoleDrawer, forKey: Keys.showConsoleDrawer) }
    }

    @Published var defaultUninstallMode: BrewStoreAppUninstallMode {
        didSet { defaults.set(defaultUninstallMode.rawValue, forKey: Keys.defaultUninstallMode) }
    }

    /// Live Periodic Auto-Refresh
    @Published var isAutoRefreshEnabled: Bool {
        didSet {
            defaults.set(isAutoRefreshEnabled, forKey: Keys.isAutoRefreshEnabled)
            NotificationCenter.default.post(name: .brewStoreAutoRefreshPreferencesDidChange, object: nil)
        }
    }

    @Published var autoRefreshIntervalSeconds: Int {
        didSet {
            let clamped = max(5, min(3600, autoRefreshIntervalSeconds))
            if autoRefreshIntervalSeconds != clamped {
                autoRefreshIntervalSeconds = clamped
            }
            defaults.set(clamped, forKey: Keys.autoRefreshIntervalSeconds)
            NotificationCenter.default.post(name: .brewStoreAutoRefreshPreferencesDidChange, object: nil)
        }
    }

    @Published var autoRefreshOnExternalBrewCommands: Bool {
        didSet {
            defaults.set(autoRefreshOnExternalBrewCommands, forKey: Keys.autoRefreshOnExternalBrewCommands)
            NotificationCenter.default.post(name: .brewStoreAutoRefreshPreferencesDidChange, object: nil)
        }
    }

    /// Automation & Background Operations
    @Published var isAutoCheckEnabled: Bool {
        didSet { defaults.set(isAutoCheckEnabled, forKey: Keys.isAutoCheckEnabled) }
    }

    @Published var checkIntervalHours: Int {
        didSet { defaults.set(checkIntervalHours, forKey: Keys.checkIntervalHours) }
    }

    @Published var autoFetchMetadata: Bool {
        didSet { defaults.set(autoFetchMetadata, forKey: Keys.autoFetchMetadata) }
    }

    @Published var autoCleanupOnQuit: Bool {
        didSet { defaults.set(autoCleanupOnQuit, forKey: Keys.autoCleanupOnQuit) }
    }

    @Published var showNotifications: Bool {
        didSet { defaults.set(showNotifications, forKey: Keys.showNotifications) }
    }

    @Published var showMenuBarBadge: Bool {
        didSet { defaults.set(showMenuBarBadge, forKey: Keys.showMenuBarBadge) }
    }

    @Published var menuBarBadgeStyle: String {
        didSet { defaults.set(menuBarBadgeStyle, forKey: Keys.menuBarBadgeStyle) }
    }

    @Published var defaultMenuBarTab: String {
        didSet { defaults.set(defaultMenuBarTab, forKey: Keys.defaultMenuBarTab) }
    }

    @Published var menuBarCloseOnAction: Bool {
        didSet { defaults.set(menuBarCloseOnAction, forKey: Keys.menuBarCloseOnAction) }
    }

    @Published var compactMenuBarView: Bool {
        didSet { defaults.set(compactMenuBarView, forKey: Keys.compactMenuBarView) }
    }

    /// Innovation Feature Flags
    @Published var enableEditorialStories: Bool {
        didSet { defaults.set(enableEditorialStories, forKey: Keys.enableEditorialStories) }
    }

    @Published var enableDeveloperStacks: Bool {
        didSet { defaults.set(enableDeveloperStacks, forKey: Keys.enableDeveloperStacks) }
    }

    @Published var enableVisualDependencyGraph: Bool {
        didSet { defaults.set(enableVisualDependencyGraph, forKey: Keys.enableVisualDependencyGraph) }
    }

    @Published var enableAppCleaner: Bool {
        didSet { defaults.set(enableAppCleaner, forKey: Keys.enableAppCleaner) }
    }

    @Published var enableAutoSnapshotBeforeMutations: Bool {
        didSet { defaults.set(enableAutoSnapshotBeforeMutations, forKey: Keys.enableAutoSnapshotBeforeMutations) }
    }

    @Published var enableAutoGistCloudSync: Bool {
        didSet { defaults.set(enableAutoGistCloudSync, forKey: Keys.enableAutoGistCloudSync) }
    }

    init() {
        // Register default values
        let registeredDefaults: [String: Any] = [
            Keys.isAutoRefreshEnabled: true,
            Keys.autoRefreshIntervalSeconds: 15,
            Keys.autoRefreshOnExternalBrewCommands: true,
            Keys.isAutoCheckEnabled: true,
            Keys.checkIntervalHours: 1,
            Keys.autoFetchMetadata: true,
            Keys.autoCleanupOnQuit: false,
            Keys.showNotifications: true,
            Keys.showMenuBarBadge: true,
            Keys.menuBarBadgeStyle: "count",
            Keys.defaultMenuBarTab: "Updates",
            Keys.menuBarCloseOnAction: false,
            Keys.compactMenuBarView: false,
            Keys.enableEditorialStories: true,
            Keys.enableDeveloperStacks: true,
            Keys.enableVisualDependencyGraph: true,
            Keys.enableAppCleaner: true,
            Keys.enableAutoSnapshotBeforeMutations: true,
            Keys.enableAutoGistCloudSync: false,
            Keys.showConsoleDrawer: false,
            Keys.hideDockIconWhenWindowClosed: true,
            Keys.confirmOperationsBeforeExecution: true,
            Keys.defaultUninstallMode: BrewStoreAppUninstallMode.preserveData.rawValue,
            Keys.defaultAppSourcePreference: AppSourcePreference.homebrew.rawValue,
            Keys.hideCompletedBundles: false,
            Keys.hideInstalledWishlist: false,
            Keys.hideIdenticalSnapshots: false,
            Keys.webhookURL: "",
            Keys.webhookEnabled: false,
            Keys.webhookNotifyOnUpdatesFound: true
        ]
        defaults.register(defaults: registeredDefaults)

        self.hideCompletedBundles = defaults.bool(forKey: Keys.hideCompletedBundles)
        self.hideInstalledWishlist = defaults.bool(forKey: Keys.hideInstalledWishlist)
        self.hideIdenticalSnapshots = defaults.bool(forKey: Keys.hideIdenticalSnapshots)

        self.confirmOperationsBeforeExecution = defaults.object(forKey: Keys.confirmOperationsBeforeExecution) != nil ? defaults.bool(forKey: Keys.confirmOperationsBeforeExecution) : true
        if let savedSource = defaults.string(forKey: Keys.defaultAppSourcePreference),
           let pref = AppSourcePreference(rawValue: savedSource) {
            self.defaultAppSourcePreference = pref
        } else {
            self.defaultAppSourcePreference = .homebrew
        }
        if let savedMode = defaults.string(forKey: Keys.defaultUninstallMode),
           let mode = BrewStoreAppUninstallMode(rawValue: savedMode) {
            self.defaultUninstallMode = mode
        } else {
            self.defaultUninstallMode = .preserveData
        }
        self.hideDockIconWhenWindowClosed = defaults.object(forKey: Keys.hideDockIconWhenWindowClosed) != nil ? defaults.bool(forKey: Keys.hideDockIconWhenWindowClosed) : true
        self.showConsoleDrawer = defaults.bool(forKey: Keys.showConsoleDrawer)
        self.isAutoRefreshEnabled = defaults.bool(forKey: Keys.isAutoRefreshEnabled)
        let savedInterval = defaults.integer(forKey: Keys.autoRefreshIntervalSeconds)
        self.autoRefreshIntervalSeconds = savedInterval > 0 ? savedInterval : 15
        self.autoRefreshOnExternalBrewCommands = defaults.bool(forKey: Keys.autoRefreshOnExternalBrewCommands)

        self.isAutoCheckEnabled = defaults.bool(forKey: Keys.isAutoCheckEnabled)
        self.checkIntervalHours = defaults.integer(forKey: Keys.checkIntervalHours) > 0 ? defaults.integer(forKey: Keys.checkIntervalHours) : 1
        self.autoFetchMetadata = defaults.object(forKey: Keys.autoFetchMetadata) != nil ? defaults.bool(forKey: Keys.autoFetchMetadata) : true
        self.autoCleanupOnQuit = defaults.bool(forKey: Keys.autoCleanupOnQuit)
        self.showNotifications = defaults.bool(forKey: Keys.showNotifications)
        self.showMenuBarBadge = defaults.bool(forKey: Keys.showMenuBarBadge)
        self.menuBarBadgeStyle = defaults.string(forKey: Keys.menuBarBadgeStyle) ?? "count"
        self.defaultMenuBarTab = defaults.string(forKey: Keys.defaultMenuBarTab) ?? "Updates"
        self.menuBarCloseOnAction = defaults.bool(forKey: Keys.menuBarCloseOnAction)
        self.compactMenuBarView = defaults.bool(forKey: Keys.compactMenuBarView)

        self.enableEditorialStories = defaults.bool(forKey: Keys.enableEditorialStories)
        self.enableDeveloperStacks = defaults.bool(forKey: Keys.enableDeveloperStacks)
        self.enableVisualDependencyGraph = defaults.bool(forKey: Keys.enableVisualDependencyGraph)
        self.enableAppCleaner = defaults.bool(forKey: Keys.enableAppCleaner)
        self.enableAutoSnapshotBeforeMutations = defaults.bool(forKey: Keys.enableAutoSnapshotBeforeMutations)
        self.enableAutoGistCloudSync = defaults.bool(forKey: Keys.enableAutoGistCloudSync)

        self.webhookURL = defaults.string(forKey: Keys.webhookURL) ?? ""
        self.webhookEnabled = defaults.bool(forKey: Keys.webhookEnabled)
        self.webhookNotifyOnUpdatesFound = defaults.object(forKey: Keys.webhookNotifyOnUpdatesFound) != nil ? defaults.bool(forKey: Keys.webhookNotifyOnUpdatesFound) : true
    }

    func resetToDefaults() {
        hideDockIconWhenWindowClosed = true
        showConsoleDrawer = false
        isAutoRefreshEnabled = true
        autoRefreshIntervalSeconds = 15
        autoRefreshOnExternalBrewCommands = true

        isAutoCheckEnabled = true
        checkIntervalHours = 1
        autoFetchMetadata = true
        autoCleanupOnQuit = false
        showNotifications = true
        showMenuBarBadge = true
        menuBarBadgeStyle = "count"
        defaultMenuBarTab = "Updates"
        menuBarCloseOnAction = false
        compactMenuBarView = false

        enableEditorialStories = true
        enableDeveloperStacks = true
        enableVisualDependencyGraph = true
        enableAppCleaner = true
        enableAutoSnapshotBeforeMutations = true
        enableAutoGistCloudSync = false
        confirmOperationsBeforeExecution = true
        defaultUninstallMode = .preserveData
        defaultAppSourcePreference = .homebrew
        hideCompletedBundles = false
        hideInstalledWishlist = false
        hideIdenticalSnapshots = false

        webhookURL = ""
        webhookEnabled = false
        webhookNotifyOnUpdatesFound = true
    }
}

extension Notification.Name {
    static let brewStoreAutoRefreshPreferencesDidChange = Notification.Name("brewStoreAutoRefreshPreferencesDidChange")
    static let brewStoreDockLifecyclePreferenceDidChange = Notification.Name("brewStoreDockLifecyclePreferenceDidChange")
}
