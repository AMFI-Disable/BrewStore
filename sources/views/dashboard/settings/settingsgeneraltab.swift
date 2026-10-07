import AppKit
import SwiftUI

struct SettingsGeneralTab: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var updateMonitor: BrewStoreUpdateMonitor

    @ObservedObject private var preferences = BrewStorePreferences.shared
    @ObservedObject private var localization = BrewStoreLocalizationManager.shared
    @StateObject private var launchAgent = BrewStoreLaunchAgentManager.shared
    @StateObject private var appUpdateChecker = BrewStoreAppUpdateChecker.shared
    @ObservedObject private var cliManager = BrewStoreCLIToolManager.shared

    @State private var isTestingWebhook = false
    @State private var webhookTestResult: (success: Bool, message: String)?
    @State private var copiedSchemeURL: String?
    @State private var showingHelpSheet = false
    @State private var showingAISheet = false
    @State private var showingShellConfigSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            autoRefreshSection
            dockAndWindowSection
            preferredAppManagerSection
            languageSection
            launchAgentSection
            appUpdatesSection
            homebrewTapSection
            cliCompanionSection
            autoUpdateSchedulerSection
            notificationsSection
            webhooksSection
            deepLinkingSection
            menuBarSection
            assistantsSection
            helpSection
        }
        .sheet(isPresented: $showingHelpSheet) {
            HelpManualView()
        }
        .sheet(isPresented: $showingAISheet) {
            AISearchView(manager: manager)
        }
        .sheet(isPresented: $showingShellConfigSheet) {
            ShellConfigView(manager: manager)
        }
    }

    // MARK: - Sections

    private var autoRefreshSection: some View {
        SettingsCardSection(title: "Live Auto-Refresh & Command Detection", icon: "arrow.clockwise.circle.fill") {
            Toggle("Auto-Refresh Catalog & Status Periodically", isOn: $preferences.isAutoRefreshEnabled)

            Text("Automatically refreshes installed packages, services, and outdated counts in the background.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if preferences.isAutoRefreshEnabled {
                Picker("Auto-Refresh Frequency", selection: $preferences.autoRefreshIntervalSeconds) {
                    Text("15 seconds (Default)").tag(15)
                    Text("30 seconds").tag(30)
                    Text("45 seconds").tag(45)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Fine-tune Interval:")
                        .font(.caption.bold())
                    Spacer()
                    Stepper(
                        value: $preferences.autoRefreshIntervalSeconds,
                        in: 5 ... 3600,
                        step: preferences.autoRefreshIntervalSeconds < 60 ? 5 : 30
                    ) {
                        Text(formatRefreshInterval(preferences.autoRefreshIntervalSeconds))
                            .font(.caption.monospaced().bold())
                    }
                }
                .padding(.top, 4)
            }

            Divider()

            Toggle("Auto-Refresh on External Terminal Commands", isOn: $preferences.autoRefreshOnExternalBrewCommands)

            Text("Monitors Homebrew's Cellar and Caskroom directories so external commands run in Terminal, iTerm2, or Ghostty refresh BrewStore automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last Refreshed").font(.caption.bold())
                    if let date = manager.lastRefreshedAt {
                        Text("\(date, style: .relative) ago (\(date, style: .time))")
                    } else {
                        Text("Not refreshed yet this session")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    manager.retryRefresh()
                } label: {
                    Label(manager.isLoading ? "Refreshing…" : "Refresh Now", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(manager.isLoading || manager.isOperating)
            }
        }
    }

    private var dockAndWindowSection: some View {
        SettingsCardSection(title: "Dock & Window Behavior", icon: "menubar.dock.rectangle") {
            Toggle("Hide Dock icon when window is closed", isOn: $preferences.hideDockIconWhenWindowClosed)

            Text("Keeps the menu bar icon and background checks running when the window is closed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var preferredAppManagerSection: some View {
        SettingsCardSection(title: "Preferred App Manager", icon: "arrow.triangle.swap") {
            Picker("Source for Dual-Available Apps", selection: $preferences.defaultAppSourcePreference) {
                ForEach(AppSourcePreference.allCases) { pref in
                    Text(pref.title).tag(pref)
                }
            }
            .pickerStyle(.menu)

            Text("Select which source to prioritize when an application is available on both Homebrew and the App Store.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        SettingsCardSection(title: "Language & Localization", icon: "globe") {
            Picker("App Display Language", selection: $localization.currentLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)

            Text("BrewStore dynamically updates labels and descriptions based on your preferred language.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var launchAgentSection: some View {
        SettingsCardSection(title: "Background Launch Agent", icon: "clock.badge.checkmark.fill") {
            Toggle("Start background checks on login", isOn: Binding(
                get: { launchAgent.isEnabled },
                set: { launchAgent.toggleLaunchAgent(enabled: $0) }
            ))

            Text("Checks for outdated packages periodically in the background.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if launchAgent.isEnabled {
                Picker("Check Frequency", selection: $launchAgent.intervalHours) {
                    Text("Every hour (Default)").tag(1)
                    Text("Every 6 hours").tag(6)
                    Text("Every 12 hours").tag(12)
                    Text("Daily (24 hours)").tag(24)
                    Text("Weekly (168 hours)").tag(168)
                }
                .onChange(of: launchAgent.intervalHours) {
                    launchAgent.installLaunchAgent()
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Last Background Run").font(.subheadline.bold())
                        Spacer()
                        if let status = launchAgent.lastStatus {
                            Text(status.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never run").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if let status = launchAgent.lastStatus {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(status.isSuccess ? (status.totalOutdated > 0 ? Color.orange : Color.green) : Color.red)
                                .frame(width: 8, height: 8)

                            Text(status.isSuccess ? (status.totalOutdated > 0 ? "\(status.totalOutdated) Outdated Packages Detected" : "All Packages Up to Date") : "Check Failed: \(status.errorMessage ?? "Error")")
                                .font(.caption.bold())
                                .foregroundStyle(status.isSuccess ? (status.totalOutdated > 0 ? Color.orange : Color.green) : Color.red)
                        }

                        if status.totalOutdated > 0 {
                            let allOutdated = status.outdatedFormulae + status.outdatedCasks
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(allOutdated, id: \.self) { pkg in
                                        Text(pkg)
                                            .font(.caption2.monospaced())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12), in: Capsule())
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        if let msg = launchAgent.statusMessage {
                            Text(msg).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(launchAgent.isRunningCheckNow ? "Running Check…" : "Run LaunchAgent Check Now") {
                            launchAgent.runCheckNow()
                        }
                        .controlSize(.small)
                        .disabled(launchAgent.isRunningCheckNow)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var appUpdatesSection: some View {
        SettingsCardSection(title: "BrewStore Application Updates", icon: "arrow.down.app.fill") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installed Version: v\(appUpdateChecker.currentVersion)").font(.subheadline.bold())
                    if let release = appUpdateChecker.latestRelease {
                        Text("Latest Release: v\(release.version)")
                            .font(.caption)
                            .foregroundStyle(appUpdateChecker.isUpdateAvailable ? Color.orange : Color.secondary)
                    }
                }
                Spacer()

                if appUpdateChecker.isUpdateAvailable {
                    Button {
                        appUpdateChecker.downloadAndOpenRelease()
                    } label: {
                        Label("Download Update (.dmg)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button(appUpdateChecker.isChecking ? "Checking…" : "Check for App Updates") {
                        appUpdateChecker.checkForAppUpdates()
                    }
                    .controlSize(.small)
                    .disabled(appUpdateChecker.isChecking)
                }
            }

            if let msg = appUpdateChecker.statusMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }

            Text("BrewStore checks for official GitHub releases. For manual installations, refer to the project documentation.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var homebrewTapSection: some View {
        SettingsCardSection(title: "Homebrew Tap for Cask & CLI", icon: "terminal.fill") {
            Text("Install or update BrewStore directly via the official Homebrew Tap:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("brew tap amfi-disable/brewstore && brew install --cask brewstore")
                .font(.caption.monospaced())
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var cliCompanionSection: some View {
        SettingsCardSection(title: "Command Line Companion (brewstore)", icon: "terminal.fill") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(cliManager.isInstalled ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(cliManager.isInstalled ? "CLI Tool Installed" : "CLI Tool Not Installed")
                            .font(.subheadline.bold())
                            .foregroundStyle(cliManager.isInstalled ? Color.primary : Color.secondary)
                    }

                    if let path = cliManager.installedPath {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Install 'brewstore' into ~/.local/bin to run CLI commands from Terminal, iTerm2, or Ghostty.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if cliManager.isInstalled {
                    Button("Uninstall CLI") {
                        cliManager.uninstallCLISymlink()
                    }
                    .controlSize(.small)
                    .disabled(cliManager.isOperating)

                    Button("Reinstall") {
                        cliManager.installCLISymlink()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(cliManager.isOperating)
                } else {
                    Button {
                        cliManager.installCLISymlink()
                    } label: {
                        Label("Install CLI Tool", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(cliManager.isOperating)
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shell Auto-Completions").font(.subheadline.bold())
                    Text("Install tab-completion scripts for Zsh (~/.zsh/completions), Bash, and Fish.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    cliManager.installShellCompletions()
                } label: {
                    Label(cliManager.completionsInstalled ? "Reinstall Completions" : "Install Completions", systemImage: "sparkles")
                }
                .controlSize(.small)
                .disabled(cliManager.isOperating)
            }

            if let status = cliManager.statusMessage {
                Text(status)
                    .font(.caption.bold())
                    .foregroundStyle(status.lowercased().contains("failed") || status.lowercased().contains("error") ? Color.red : Color.green)
                    .padding(.top, 2)
            }

            HStack {
                Text("PATH Configuration:")
                    .font(.caption2.bold())
                Text("export PATH=\"$HOME/.local/bin:$PATH\"")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("export PATH=\"$HOME/.local/bin:$PATH\"", forType: .string)
                }
                .controlSize(.mini)
            }
        }
    }

    private var autoUpdateSchedulerSection: some View {
        SettingsCardSection(title: "Update Scheduler", icon: "arrow.triangle.2.circlepath.circle.fill") {
            Picker("Auto-Update Check Frequency", selection: Binding(
                get: { BrewStoreAutoUpdateScheduler.shared.frequency },
                set: { BrewStoreAutoUpdateScheduler.shared.frequency = $0 }
            )) {
                ForEach(AutoUpdateFrequency.allCases) { freq in
                    Text(freq.rawValue).tag(freq)
                }
            }

            Picker("Auto-Upgrade Policy", selection: Binding(
                get: { BrewStoreAutoUpdateScheduler.shared.upgradeMode },
                set: { BrewStoreAutoUpdateScheduler.shared.upgradeMode = $0 }
            )) {
                ForEach(AutoUpgradeMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("Deliver macOS notification when auto-upgrades complete", isOn: Binding(
                get: { BrewStoreAutoUpdateScheduler.shared.autoNotifyOnUpdates },
                set: { BrewStoreAutoUpdateScheduler.shared.autoNotifyOnUpdates = $0 }
            ))

            HStack {
                if let lastDate = BrewStoreAutoUpdateScheduler.shared.lastCheckDate {
                    Text("Last checked: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check & Upgrade Now") {
                    BrewStoreAutoUpdateScheduler.shared.performSilentUpdateCheck()
                }
                .controlSize(.small)
            }
        }
    }

    private var notificationsSection: some View {
        SettingsCardSection(title: "System Notifications", icon: "bell.badge.fill") {
            Toggle("Deliver notification alerts when updates are found", isOn: $preferences.showNotifications)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("macOS Notification Permission")
                    Spacer()
                    switch updateMonitor.notificationStatus {
                    case .authorized:
                        Label("Authorized", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption.bold())
                    case .denied:
                        HStack(spacing: 8) {
                            Label("Denied", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption.bold())

                            Button("Open Notification Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    default:
                        Button("Request Permission", action: updateMonitor.requestNotificationAuthorization)
                            .controlSize(.small)
                    }
                }

                if updateMonitor.notificationStatus == .denied {
                    Text("System notifications are disabled for BrewStore. You won't receive background alerts for pending package updates or completed auto-upgrades.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var webhooksSection: some View {
        SettingsCardSection(title: "Webhooks & Automation", icon: "antenna.radiowaves.left.and.right") {
            Toggle("Enable Webhook Notifications", isOn: $preferences.webhookEnabled)

            Text("Send JSON notifications to Discord, Slack, or a custom automation endpoint when updates are available or auto-upgrades finish.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if preferences.webhookEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Webhook Endpoint URL").font(.caption.bold())
                    TextField("https://discord.com/api/webhooks/... or https://hooks.slack.com/...", text: $preferences.webhookURL)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Send notification when new updates are found", isOn: $preferences.webhookNotifyOnUpdatesFound)

                HStack {
                    Button(isTestingWebhook ? "Sending Test…" : "Send Test Webhook") {
                        isTestingWebhook = true
                        webhookTestResult = nil
                        Task {
                            let result = await BrewStoreAutoUpdateScheduler.testWebhook(urlString: preferences.webhookURL)
                            isTestingWebhook = false
                            webhookTestResult = result
                        }
                    }
                    .controlSize(.small)
                    .disabled(isTestingWebhook || preferences.webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if isTestingWebhook {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()

                    if let res = webhookTestResult {
                        HStack(spacing: 4) {
                            Image(systemName: res.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(res.success ? .green : .red)
                            Text(res.message)
                                .font(.caption2.bold())
                                .foregroundStyle(res.success ? .green : .red)
                        }
                    }
                }
            }
        }
    }

    private var deepLinkingSection: some View {
        SettingsCardSection(title: "Raycast, Alfred & Shortcuts Deep-Linking", icon: "link.circle.fill") {
            Text("Control BrewStore directly from macOS Shortcuts, Raycast Quicklinks, Alfred, or terminal scripts using the native `brewstore://` URL scheme.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                schemeRow(label: "Upgrade All Packages", url: "brewstore://update-all", desc: "Launches BrewStore and runs brew upgrade on all outdated packages.")
                schemeRow(label: "Deep Clean Caches", url: "brewstore://clean", desc: "Runs brew cleanup to prune downloads and stale build artifacts.")
                schemeRow(label: "Search Packages", url: "brewstore://search?q=ripgrep", desc: "Opens BrewStore directly to search results for a given query.")
                schemeRow(label: "Inspect Formula / Cask", url: "brewstore://package?id=docker", desc: "Navigates straight to the package detail modal.")
                schemeRow(label: "Open Blueprints & Stacks", url: "brewstore://blueprints", desc: "Navigates to developer toolkits and blueprint captures.")
                schemeRow(label: "Batch Install Packages", url: "brewstore://quick-install?packages=bat,eza,fzf", desc: "Queues a comma-separated list of packages for 1-click installation.")
            }
        }
    }

    private var menuBarSection: some View {
        SettingsCardSection(title: "Menu Bar Companion", icon: "menubar.rectangle") {
            Toggle("Show badge for outdated packages in Menu Bar icon", isOn: $preferences.showMenuBarBadge)

            if preferences.showMenuBarBadge {
                Picker("Badge Style", selection: $preferences.menuBarBadgeStyle) {
                    Text("Number Count (e.g. 3)").tag("count")
                    Text("Status Indicator Dot").tag("dot")
                }
            }

            Picker("Default Open Tab", selection: $preferences.defaultMenuBarTab) {
                Text("Updates").tag("Updates")
                Text("Services").tag("Services")
                Text("Tools").tag("Tools")
            }

            Toggle("Automatically purge stale download cache on exit (brew cleanup)", isOn: $preferences.autoCleanupOnQuit)
        }
    }

    private var assistantsSection: some View {
        SettingsCardSection(title: "Smart Assistants & Tools", icon: "wand.and.stars") {
            Text("Access AI-powered natural language package discovery and shell environment configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    showingAISheet = true
                } label: {
                    Label("AI Package Assistant", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    showingShellConfigSheet = true
                } label: {
                    Label("Shell Setup Assistant", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var helpSection: some View {
        SettingsCardSection(title: "Help & Documentation", icon: "book.fill") {
            Text("Learn how to use Storefront discovery, daemon management, App Cleaner, and shortcuts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    showingHelpSheet = true
                } label: {
                    Label("Open Help Manual (⌘?)", systemImage: "questionmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Link("Homebrew Docs", destination: URL(string: "https://docs.brew.sh") ?? URL(fileURLWithPath: "/"))
                    .font(.caption)
            }
        }
    }

    private func schemeRow(label: String, url: String, desc: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label).font(.caption.bold())
                    Text(url).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Text(desc).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(copiedSchemeURL == url ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                copiedSchemeURL = url
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedSchemeURL == url {
                        copiedSchemeURL = nil
                    }
                }
            }
            .controlSize(.mini)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }
}
