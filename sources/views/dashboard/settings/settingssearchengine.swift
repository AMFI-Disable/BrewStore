import Foundation

struct SettingsSearchItem: Identifiable, Hashable, Sendable {
    let id: String
    let tab: SettingsTab
    let title: String
    let summary: String
    let keywords: [String]
    let icon: String

    var breadcrumb: String {
        "\(tab.rawValue) › \(title)"
    }
}

enum SettingsSearchEngine {
    static let allItems: [SettingsSearchItem] = [
        // MARK: - General Tab
        SettingsSearchItem(
            id: "general_autorefresh",
            tab: .general,
            title: "Live Auto-Refresh & Command Detection",
            summary: "Automatically refreshes installed packages, services, and outdated counts in the background and on external terminal commands.",
            keywords: ["auto-refresh", "refresh", "interval", "frequency", "stepper", "cellar", "caskroom", "terminal", "ghostty", "iterm2"],
            icon: "arrow.clockwise.circle.fill"
        ),
        SettingsSearchItem(
            id: "general_dock_window",
            tab: .general,
            title: "Dock, Window & Launch Behavior",
            summary: "Hide Dock icon when all windows are closed, and control app startup and menu bar behaviors.",
            keywords: ["dock", "window", "hide dock", "close window", "quit", "minimize", "startup"],
            icon: "macwindow"
        ),
        SettingsSearchItem(
            id: "general_preferred_app_manager",
            tab: .general,
            title: "Preferred Application Manager",
            summary: "Choose whether to prioritize Homebrew Cask or Mac App Store for dual-available applications.",
            keywords: ["app store", "mac app store", "mas", "cask", "priority", "source", "dual", "installer"],
            icon: "arrow.triangle.branch"
        ),
        SettingsSearchItem(
            id: "general_language",
            tab: .general,
            title: "Application Language & Localization",
            summary: "Change BrewStore interface display language across English, Simplified Chinese, Traditional Chinese, Japanese, German, French, and Spanish.",
            keywords: ["language", "localization", "translate", "locale", "english", "chinese", "japanese", "german", "french", "spanish"],
            icon: "globe"
        ),
        SettingsSearchItem(
            id: "general_launch_agent",
            tab: .general,
            title: "Background Launch Agent (Auto-Start)",
            summary: "Install or remove the background launch agent to automatically run BrewStore on login.",
            keywords: ["launch agent", "autostart", "login item", "boot", "startup", "daemon", "plist"],
            icon: "play.circle.fill"
        ),
        SettingsSearchItem(
            id: "general_app_updates",
            tab: .general,
            title: "BrewStore Application Updates",
            summary: "Check for new versions of BrewStore from GitHub releases and enable automatic update checks.",
            keywords: ["update app", "version", "github releases", "check for updates", "sparkle", "upgrade"],
            icon: "arrow.down.circle.fill"
        ),
        SettingsSearchItem(
            id: "general_tap",
            tab: .general,
            title: "Official BrewStore Homebrew Tap",
            summary: "Inspect and manage the official BrewStore tap (even/brewstore) for casks and formulas.",
            keywords: ["tap", "official tap", "cask tap", "formula tap", "repository"],
            icon: "spigot.fill"
        ),
        SettingsSearchItem(
            id: "general_cli_companion",
            tab: .general,
            title: "BrewStore CLI Companion Tool",
            summary: "Install the brewstore command-line tool into /usr/local/bin or /opt/homebrew/bin for terminal access.",
            keywords: ["cli", "companion", "command line", "symlink", "terminal", "bin", "shell"],
            icon: "terminal"
        ),
        SettingsSearchItem(
            id: "general_scheduler",
            tab: .general,
            title: "Update Scheduler",
            summary: "Schedule automatic background checks for outdated Homebrew packages and dependencies.",
            keywords: ["scheduler", "schedule", "interval", "hours", "auto-update", "outdated", "background check"],
            icon: "clock.badge.checkmark.fill"
        ),
        SettingsSearchItem(
            id: "general_notifications",
            tab: .general,
            title: "Desktop Notifications & Alerts",
            summary: "Configure macOS notifications for available updates, successful installs, and service failures.",
            keywords: ["notifications", "alerts", "banner", "sound", "badge", "updates notification"],
            icon: "bell.badge.fill"
        ),
        SettingsSearchItem(
            id: "general_webhooks",
            tab: .general,
            title: "Webhooks & Automation Integration",
            summary: "Trigger outgoing HTTP webhooks on package installs, upgrades, and uninstalls for Slack, Discord, or custom servers.",
            keywords: ["webhook", "http post", "slack", "discord", "payload", "automation", "url"],
            icon: "network.badge.shield.half.filled"
        ),
        SettingsSearchItem(
            id: "general_deep_linking",
            tab: .general,
            title: "URL Scheme & Deep Linking",
            summary: "Handle brewstore:// URLs for opening packages, search, updates, and settings from browser or terminal.",
            keywords: ["url scheme", "deep link", "brewstore://", "uri", "scheme", "open link"],
            icon: "link"
        ),
        SettingsSearchItem(
            id: "general_menubar",
            tab: .general,
            title: "Menu Bar Companion",
            summary: "Configure menu bar item, badge counts, compact view, and quick action behaviors.",
            keywords: ["menu bar", "menubar", "status bar", "tray", "badge", "compact"],
            icon: "menubar.rectangle"
        ),
        SettingsSearchItem(
            id: "general_assistants",
            tab: .general,
            title: "AI & Shell Assistant Tools",
            summary: "AI natural language package search and shell configuration exporter (zsh, bash, fish).",
            keywords: ["ai", "natural language", "llm", "search assistant", "shell config", "export path", "zsh", "bash", "fish"],
            icon: "sparkles"
        ),
        SettingsSearchItem(
            id: "general_help",
            tab: .general,
            title: "Help, Documentation & Support",
            summary: "User guide, keyboard shortcuts, troubleshooting guide, and feedback links.",
            keywords: ["help", "manual", "documentation", "guide", "keyboard shortcuts", "faq", "support"],
            icon: "questionmark.circle.fill"
        ),

        // MARK: - Appearance Tab
        SettingsSearchItem(
            id: "appearance_themes",
            tab: .appearance,
            title: "Custom Accent Themes",
            summary: "Choose accent color themes: Amber Brew, Terminal Green, Ocean Blue, Cyberpunk Purple, Graphite, etc.",
            keywords: ["theme", "accent", "color", "amber", "green", "blue", "purple", "graphite", "palette", "dark mode", "light mode"],
            icon: "paintbrush.fill"
        ),
        SettingsSearchItem(
            id: "appearance_vibrancy",
            tab: .appearance,
            title: "Window Glassmorphism & Vibrancy",
            summary: "Adjust macOS window translucency and background vibrancy blending (Standard, Vibrant, Ultra-Translucent, Opaque).",
            keywords: ["vibrancy", "glassmorphism", "translucency", "blur", "transparent", "window material"],
            icon: "macwindow.on.rectangle"
        ),
        SettingsSearchItem(
            id: "appearance_declutter",
            tab: .appearance,
            title: "Clean Interface & Decluttering",
            summary: "Hide completed bundles, hide installed items in wishlist, and hide identical snapshots.",
            keywords: ["declutter", "hide", "bundles", "wishlist", "snapshots", "clean interface", "minimal"],
            icon: "eye.slash.fill"
        ),

        // MARK: - Features Tab
        SettingsSearchItem(
            id: "features_modules",
            tab: .features,
            title: "Storefront Modules",
            summary: "Toggle Editorial Stories and Developer Toolkits in the sidebar and storefront.",
            keywords: ["editorial stories", "toolkits", "developer stacks", "discovery modules", "articles", "suites"],
            icon: "sparkles"
        ),
        SettingsSearchItem(
            id: "features_details",
            tab: .features,
            title: "Package Details",
            summary: "Dependency graphs, App Cleaner leftover scanner, and default uninstallation strategy.",
            keywords: ["dependency graph", "app cleaner", "residuals", "caches", "leftovers", "uninstall mode", "clean uninstall"],
            icon: "cube.transparent"
        ),
        SettingsSearchItem(
            id: "features_safety_sync",
            tab: .features,
            title: "Backups & Sync",
            summary: "Automatically create snapshot before package mutations and sync Brewfile to GitHub Gist.",
            keywords: ["snapshot", "safety", "cloud sync", "gist", "github gist", "auto backup", "rollback safety"],
            icon: "shield.lefthalf.filled"
        ),
        SettingsSearchItem(
            id: "features_watchdog",
            tab: .features,
            title: "Service Watchdog",
            summary: "Monitor Homebrew background services and automatically restart stopped daemons.",
            keywords: ["watchdog", "services", "daemon", "auto-restart", "crash recovery", "mysql", "postgres", "redis", "nginx"],
            icon: "bolt.shield.fill"
        ),

        // MARK: - Network Tab
        SettingsSearchItem(
            id: "network_benchmark",
            tab: .network,
            title: "Mirror Benchmark & Speed Ranking",
            summary: "Benchmark latency and download throughput across official Homebrew, USTC, Tuna, Aliyun, and BFSU mirrors.",
            keywords: ["benchmark", "mirror latency", "ping", "fastest mirror", "ranking", "speed test"],
            icon: "chart.bar.xaxis"
        ),
        SettingsSearchItem(
            id: "network_speedtest",
            tab: .network,
            title: "Download Speed Test (speedtest-go)",
            summary: "Measure network bandwidth using speedtest-go to estimate package download speeds.",
            keywords: ["speed test", "bandwidth", "download speed", "mbps", "speedtest", "latency"],
            icon: "speedometer"
        ),
        SettingsSearchItem(
            id: "network_mirrors",
            tab: .network,
            title: "Homebrew Mirrors & Upstream Sources",
            summary: "Switch Homebrew git and bottle mirrors (Tsinghua TUNA, USTC, Alibaba Cloud, Tencent Cloud, Official).",
            keywords: ["mirror", "tuna", "ustc", "aliyun", "bottles", "upstream", "git mirror", "source", "china mirror"],
            icon: "network"
        ),
        SettingsSearchItem(
            id: "network_prefix",
            tab: .network,
            title: "Homebrew Prefix & Dual-Architecture Switcher",
            summary: "Switch active Homebrew prefix between Apple Silicon (/opt/homebrew) and Intel Rosetta 2 (/usr/local).",
            keywords: ["prefix", "apple silicon", "arm64", "intel", "x86_64", "rosetta", "opt homebrew", "usr local", "dual architecture"],
            icon: "cpu"
        ),

        // MARK: - Snapshots Tab
        SettingsSearchItem(
            id: "snapshots_gist",
            tab: .snapshots,
            title: "Multi-Machine Sync (GitHub Gist)",
            summary: "Synchronize installed formulae, casks, and taps across multiple Macs using secret GitHub Gists.",
            keywords: ["gist", "multi-machine", "sync", "github token", "cloud", "cross-mac", "restore across macs"],
            icon: "arrow.triangle.2.circlepath.circle.fill"
        ),
        SettingsSearchItem(
            id: "snapshots_dotfiles",
            tab: .snapshots,
            title: "Dotfiles & Auto-Sync",
            summary: "Automatically export Brewfile to your local dotfiles repository whenever packages change.",
            keywords: ["dotfiles", "auto-sync", "git repo", "brewfile path", "export dotfiles"],
            icon: "folder.badge.gearshape"
        ),
        SettingsSearchItem(
            id: "snapshots_export",
            tab: .snapshots,
            title: "Brewfile Export",
            summary: "Export current Homebrew installation manifest into a standard Brewfile.",
            keywords: ["export", "brewfile", "dump", "manifest", "save brewfile", "backup brewfile"],
            icon: "square.and.arrow.up.fill"
        ),
        SettingsSearchItem(
            id: "snapshots_import",
            tab: .snapshots,
            title: "Brewfile Import & Diff",
            summary: "Import a Brewfile, view visual diff against installed packages, and install missing packages.",
            keywords: ["import", "brewfile", "diff", "compare", "install missing", "bundle install"],
            icon: "square.and.arrow.down.fill"
        ),
        SettingsSearchItem(
            id: "snapshots_rollback",
            tab: .snapshots,
            title: "Snapshot Rollback & Disaster Recovery",
            summary: "Restore previous Homebrew snapshots, rollback unwanted upgrades, and undo package changes.",
            keywords: ["snapshot", "rollback", "undo", "restore", "disaster recovery", "history rollback"],
            icon: "clock.arrow.circlepath"
        ),

        // MARK: - Doctor Tab
        SettingsSearchItem(
            id: "doctor_diagnostics",
            tab: .doctor,
            title: "Homebrew System Diagnostics (brew doctor)",
            summary: "Run brew doctor to diagnose configuration errors, unlinked kegs, broken symlinks, and outdated Xcode tools.",
            keywords: ["doctor", "diagnostics", "warnings", "clt", "command line tools", "brew doctor", "health", "fix"],
            icon: "stethoscope"
        ),
        SettingsSearchItem(
            id: "doctor_maintenance",
            tab: .doctor,
            title: "Maintenance & Integrity Tools",
            summary: "Orphan & Keg Auditor, Bottle Integrity Auditor, Tap Health Benchmark, Cask Quarantine Auditor, Source Build Studio.",
            keywords: ["maintenance", "orphan", "keg", "broken symlink", "bottle integrity", "sha256", "quarantine", "source build"],
            icon: "wrench.and.screwdriver.fill"
        ),

        // MARK: - Storage Tab
        SettingsSearchItem(
            id: "storage_breakdown",
            tab: .storage,
            title: "Disk Storage Breakdown & Usage",
            summary: "Inspect total disk usage across Cellar formulae, Caskroom apps, and downloaded cache files.",
            keywords: ["disk space", "storage", "usage", "cellar", "caskroom", "cache", "gigabytes", "mb", "recalculate"],
            icon: "internaldrive.fill"
        ),
        SettingsSearchItem(
            id: "storage_privacy",
            tab: .storage,
            title: "Privacy & Analytics Policy",
            summary: "BrewStore 100% local privacy guarantee and toggle for Homebrew upstream anonymous CLI analytics.",
            keywords: ["privacy", "analytics", "tracking", "telemetry", "anonymous", "brew analytics"],
            icon: "hand.raised.fill"
        ),
        SettingsSearchItem(
            id: "storage_history",
            tab: .storage,
            title: "Operation History & Audit Log",
            summary: "View and export chronological audit log of all package installs, upgrades, and uninstalls.",
            keywords: ["history", "audit log", "operations", "transactions", "log", "export log"],
            icon: "list.bullet.rectangle"
        ),
        SettingsSearchItem(
            id: "storage_reset",
            tab: .storage,
            title: "Reset & Data Management",
            summary: "Clear Homebrew download cache, reset BrewStore preferences, or perform a complete factory reset.",
            keywords: ["reset", "clear cache", "factory reset", "clean cache", "wipe", "preferences", "danger zone"],
            icon: "trash.fill"
        )
    ]

    static func search(query: String) -> [SettingsSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        return allItems.filter { item in
            if item.title.localizedCaseInsensitiveContains(trimmed) { return true }
            if item.summary.localizedCaseInsensitiveContains(trimmed) { return true }
            if item.tab.rawValue.localizedCaseInsensitiveContains(trimmed) { return true }
            return item.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }
}
