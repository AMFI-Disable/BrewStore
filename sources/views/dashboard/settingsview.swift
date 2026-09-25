import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case features = "Features"
    case network = "Network & Mirrors"
    case snapshots = "Snapshots & Brewfile"
    case doctor = "Doctor & Health"
    case storage = "Storage & Privacy"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .features: "sparkles"
        case .network: "network"
        case .snapshots: "clock.arrow.circlepath"
        case .doctor: "stethoscope"
        case .storage: "externaldrive.fill"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var updateMonitor: BrewStoreUpdateMonitor
    var discovery: BrewStoreDiscoveryCatalog = BrewStoreDiscoveryCatalog()
    @ObservedObject var preferences = BrewStorePreferences.shared
    @ObservedObject private var resetManager = BrewStoreResetManager.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var showingUpgradeConfirmation = false
    @State private var showingDoctorSheet = false
    @State private var showingBrewfileImporter = false
    @State private var showingBrewfileConfirmation = false
    @State private var selectedBrewfileURL: URL?
    @State private var brewfileContents = ""
    @State private var brewfileError: String?
    @State private var brewfileDiff: BrewStoreBrewfileDiff?
    @State private var showingHelpSheet = false
    @State private var showingAISheet = false
    @State private var showingShellConfigSheet = false

    @ObservedObject private var localization = BrewStoreLocalizationManager.shared
    @ObservedObject private var themeManager = BrewStoreThemeVibrancyManager.shared
    @StateObject private var mirrorManager = BrewStoreMirrorManager()
    @StateObject private var prefixManager = BrewStorePrefixManager.shared
    @StateObject private var watchdog = BrewStoreServiceWatchdog.shared
    @StateObject private var snapshotManager = BrewStoreSnapshotManager()
    @StateObject private var rollbackManager = BrewStoreSnapshotRollbackManager.shared
    @StateObject private var launchAgent = BrewStoreLaunchAgentManager.shared
    @StateObject private var appUpdateChecker = BrewStoreAppUpdateChecker.shared
    @StateObject private var speedTestManager = BrewStoreSpeedTestManager.shared
    @ObservedObject private var cliManager = BrewStoreCLIToolManager.shared
    @State private var selectedRollbackSnapshot: BrewStoreSnapshot?
    @State private var showingRollbackConfirmation = false
    @State private var pendingRollbackPlan: SnapshotRollbackPlan?
    @State private var copiedMirrorConfig = false
    @State private var showingResetPreferencesConfirm = false
    @State private var showingClearCacheConfirm = false
    @State private var showingResetWishlistConfirm = false
    @State private var showingResetPinsConfirm = false
    @State private var showingClearLogsConfirm = false
    @State private var showingResetAppearanceConfirm = false
    @State private var isTestingWebhook = false
    @State private var webhookTestResult: (success: Bool, message: String)?
    @State private var copiedSchemeURL: String?
    @State private var showingDualArchBridge = false

    private var doctorDiagnostics: [BrewStoreDoctorDiagnostic] {
        BrewStoreDoctorParser.parse(manager.outputLog)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Settings Top Header / Tab Bar
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Settings").font(.largeTitle.bold())
                    Text("Manage updates, appearance, package sources, backups, and privacy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.clearPersonalSettings]) {
                        resetManager.restoreDefaultSettings()
                    }
                } label: {
                    Label("Restore Default Settings", systemImage: "sparkles")
                }
                .controlSize(.small)
                .help("Reset all settings to default (15s live refresh, 1h background checks, and recommended features enabled).")

                Button {
                    resetManager.showingResetSheet = true
                } label: {
                    Label("Reset BrewStore…", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)

            // Segmented Picker (Scrollable horizontally to guarantee tab names never truncate)
            ScrollView(.horizontal, showsIndicators: false) {
                Picker("", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Spacing.lg)
            }
            .padding(.bottom, Spacing.sm)

            Divider()

            // Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    switch selectedTab {
                    case .general:
                        generalSection
                    case .appearance:
                        appearanceSection
                    case .features:
                        featuresSection
                    case .network:
                        networkSection
                    case .snapshots:
                        snapshotsSection
                    case .doctor:
                        doctorSection
                    case .storage:
                        storageSection
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .id(selectedTab)
            .animation(nil, value: selectedTab)
        }
        .confirmationDialog("Upgrade all Homebrew packages?", isPresented: $showingUpgradeConfirmation, titleVisibility: .visible) {
            Button("Upgrade all packages", role: .destructive) { manager.upgradeAllPackages() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("BrewStore will run brew upgrade for all outdated formulae and casks.")
        }
        .fileImporter(isPresented: $showingBrewfileImporter, allowedContentTypes: [.data, .plainText], allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                do {
                    selectedBrewfileURL = url
                    let contents = try String(contentsOf: url, encoding: .utf8)
                    brewfileContents = contents
                    let parsed = BrewStoreBrewfileParser.parse(contents)
                    brewfileDiff = BrewStoreBrewfileParser.diff(parsed, installedPackages: manager.packages, installedTaps: manager.taps)
                    brewfileError = nil
                } catch {
                    brewfileContents = ""
                    brewfileDiff = nil
                    brewfileError = "Could not read the selected Brewfile: \(error.localizedDescription)"
                }
            case let .failure(error):
                brewfileError = "Could not select a Brewfile: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showingDoctorSheet) {
            DoctorDiagnosticsSheet(manager: manager, diagnostics: doctorDiagnostics)
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
        .sheet(isPresented: $resetManager.showingResetSheet) {
            ResetViewSheet(manager: manager, discovery: discovery)
        }
        .sheet(isPresented: $showingDualArchBridge) {
            DualArchitectureBridgeView(manager: manager)
        }
        .confirmationDialog("Install this Brewfile?", isPresented: $showingBrewfileConfirmation, titleVisibility: .visible) {
            Button("Install Brewfile", role: .destructive) {
                if let selectedBrewfileURL {
                    manager.installBrewfile(from: selectedBrewfileURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homebrew will install any missing formulae, casks, and taps listed in this file.")
        }
        .confirmationDialog("Rollback System to Snapshot?", isPresented: $showingRollbackConfirmation, titleVisibility: .visible) {
            Button("Rollback & Revert Packages", role: .destructive) {
                if let plan = pendingRollbackPlan {
                    rollbackManager.executeRollback(plan: plan, manager: manager)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let plan = pendingRollbackPlan {
                Text("This will uninstall \(plan.packagesToUninstall.count) packages added since the snapshot and reinstall \(plan.packagesToReinstall.count) missing packages.")
            } else {
                Text("Reverting your packages to this snapshot.")
            }
        }
    }

    // MARK: - 1. General & Automation

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardSection(title: "Live Auto-Refresh & Command Detection", icon: "arrow.clockwise.circle.fill") {
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

                    // Custom Interval Stepper
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

            cardSection(title: "Dock & Window Behavior", icon: "menubar.dock.rectangle") {
                Toggle("Hide from Dock when window is closed (Keep Menu Bar active)", isOn: $preferences.hideDockIconWhenWindowClosed)

                Text(
                    "When enabled, closing BrewStore's window hides it from the macOS Dock and ⌘Tab switcher " +
                        "while keeping the Menu Bar mug icon and background checks active. Click the Menu Bar icon " +
                        "or open BrewStore from Applications to restore the window."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            cardSection(title: "Preferred App Manager", icon: "arrow.triangle.swap") {
                Picker("Source for Dual-Available Apps", selection: $preferences.defaultAppSourcePreference) {
                    ForEach(AppSourcePreference.allCases) { pref in
                        Text(pref.title).tag(pref)
                    }
                }
                .pickerStyle(.menu)

                Text(
                    "When an application is available on both Homebrew and the Mac App Store, " +
                        "BrewStore recommends Homebrew for faster updates, CLI scriptability, and zero Apple ID prompts."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            cardSection(title: "Language & Localization", icon: "globe") {
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

            cardSection(title: "macOS Background LaunchAgent", icon: "clock.badge.checkmark.fill") {
                Toggle("Run background check LaunchAgent (Runs even when BrewStore is closed)", isOn: Binding(
                    get: { launchAgent.isEnabled },
                    set: { launchAgent.toggleLaunchAgent(enabled: $0) }
                ))

                Text("Background checking is non-destructive. Automatic upgrades remain strictly disabled by default.")
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

                    // Last Run & Result
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

            cardSection(title: "BrewStore Application Updates", icon: "arrow.down.app.fill") {
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

            cardSection(title: "Homebrew Tap for Cask & CLI", icon: "terminal.fill") {
                Text("Install or update BrewStore directly via the official Homebrew Tap:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("brew tap amfi-disable/brewstore && brew install --cask brewstore")
                    .font(.caption.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }

            cardSection(title: "Command Line Companion (brewstore)", icon: "terminal.fill") {
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

            cardSection(title: "Background Auto-Updating & Auto-Upgrading", icon: "arrow.triangle.2.circlepath.circle.fill") {
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

            cardSection(title: "System Notifications", icon: "bell.badge.fill") {
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

            cardSection(title: "Webhooks & Automation", icon: "antenna.radiowaves.left.and.right") {
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

            cardSection(title: "Raycast, Alfred & Shortcuts Deep-Linking", icon: "link.circle.fill") {
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

            cardSection(title: "Menu Bar Companion", icon: "menubar.rectangle") {
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

            cardSection(title: "Smart Assistants & Tools", icon: "wand.and.stars") {
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

            cardSection(title: "Help & Documentation", icon: "book.fill") {
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
    }

    // MARK: - 2. Innovations & Modules

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Customize BrewStore's innovation modules and discovery experiences.")
                .font(.body)
                .foregroundStyle(.secondary)

            cardSection(title: "Storefront & Discovery Modules", icon: "sparkles") {
                Toggle("Editorial Stories & Curated Deep-Dives", isOn: $preferences.enableEditorialStories)
                Text("Long-form articles with 1-click package install pills in the sidebar and storefront.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Developer Toolkits & Stacks", isOn: $preferences.enableDeveloperStacks)
                Text("Curated 1-click bundle suites for Web, Mobile, Data, and System engineering.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            cardSection(title: "Package Detail Innovations", icon: "cube.transparent") {
                Toggle("Visual Dependency Graphs", isOn: $preferences.enableVisualDependencyGraph)
                Text("Render interactive visual relationship trees showing direct and required packages.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("App Cleaner (Residual File Scanner)", isOn: $preferences.enableAppCleaner)
                Text("Scan Application Support, Caches, and preference leftovers when uninstalling Casks.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Default App Replacement & Uninstallation Strategy")
                        .font(.body)
                    Picker("", selection: $preferences.defaultUninstallMode) {
                        ForEach(BrewStoreAppUninstallMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text(preferences.defaultUninstallMode.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            cardSection(title: "Safety & Cloud Sync Policies", icon: "shield.lefthalf.filled") {
                Toggle("Auto-Snapshot before destructive package uninstallations", isOn: $preferences.enableAutoSnapshotBeforeMutations)
                Text("Automatically records Time-Machine Brewfile snapshots before removing packages.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Auto-Sync Brewfile to GitHub Private Gist on changes", isOn: $preferences.enableAutoGistCloudSync)
                Text("Automatically push cloud backups when packages or taps are altered.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            cardSection(title: "Background Service Crash Watchdog", icon: "shield.checkered") {
                Toggle("Monitor active background services for crashes", isOn: $watchdog.isWatchdogEnabled)
                Text("Periodically inspects daemons (Redis, Postgres, Nginx) and alerts if a service crashes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if watchdog.isWatchdogEnabled {
                    Divider()
                    Toggle("Auto-Restart crashed services automatically", isOn: $watchdog.autoRestartOnCrash)
                    Text("Immediately attempts to relaunch any daemon that exits with an error status.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 3. Network & Mirrors

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            MirrorBenchmarkView(manager: manager, mirrorManager: mirrorManager)

            cardSection(title: "Download Speed Test (speedtest-go)", icon: "speedometer") {
                Text("Uses speedtest-go to measure connection speed and estimate package download times.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if speedTestManager.isAvailable {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("speedtest-go Active")
                                .font(.subheadline.bold())
                            if let path = speedTestManager.binaryPath {
                                Text(path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(speedTestManager.formattedSpeed)
                                .font(.subheadline.bold())
                                .foregroundStyle(speedTestManager.currentDownloadSpeedMBps != nil ? .primary : .secondary)
                            if let at = speedTestManager.lastMeasuredAt {
                                Text("Updated \(at.formatted(date: .omitted, time: .standard))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    Toggle("Periodic Background Speed Testing", isOn: $speedTestManager.isPeriodicEnabled)

                    if speedTestManager.isPeriodicEnabled {
                        Picker("Measurement Frequency", selection: $speedTestManager.intervalSeconds) {
                            Text("15 seconds (Fastest)").tag(15)
                            Text("30 seconds").tag(30)
                            Text("1 minute").tag(60)
                            Text("2 minutes").tag(120)
                            Text("5 minutes").tag(300)
                            Text("15 minutes").tag(900)
                        }
                    }

                    HStack {
                        Button(speedTestManager.isRunningTest ? "Testing Speed…" : "Run Speed Test Now") {
                            speedTestManager.runSpeedTest(force: true)
                        }
                        .controlSize(.small)
                        .disabled(speedTestManager.isRunningTest)

                        if speedTestManager.isRunningTest {
                            ProgressView().controlSize(.small)
                        }

                        Spacer()

                        if let err = speedTestManager.lastErrorMessage {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("speedtest-go Not Installed")
                                .font(.subheadline.bold())
                            Text("Install speedtest-go to get accurate download time estimates for packages.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Install speedtest-go") {
                            speedTestManager.installSpeedTest(manager: manager)
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            cardSection(title: "Homebrew Mirrors & CDN Presets", icon: "network") {
                Text("Select an optimized regional mirror to accelerate Homebrew bottle downloads and API queries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Active Mirror", selection: $mirrorManager.selectedPresetID) {
                    ForEach(BrewStoreMirrorPreset.allPresets) { preset in
                        HStack {
                            Text(preset.name)
                            if let latency = mirrorManager.formattedLatency(for: preset) {
                                Text("(\(latency))").foregroundStyle(.secondary)
                            }
                        }
                        .tag(preset.id)
                    }
                }

                HStack {
                    Button(mirrorManager.isTestingLatency ? "Testing Latencies…" : "Test Mirror Latencies") {
                        mirrorManager.testLatencies()
                    }
                    .controlSize(.small)
                    .disabled(mirrorManager.isTestingLatency)

                    Spacer()

                    let exportScript = """
                    export HOMEBREW_API_DOMAIN="\(mirrorManager.currentPreset.brewApiDomain)"
                    export HOMEBREW_BOTTLE_DOMAIN="\(mirrorManager.currentPreset.brewBottlesDomain)"
                    """

                    Button(copiedMirrorConfig ? "Copied!" : "Copy Shell Config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(exportScript, forType: .string)
                        copiedMirrorConfig = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedMirrorConfig = false }
                    }
                    .controlSize(.small)
                }
            }

            cardSection(title: "Dual-Homebrew Prefix & Architecture Switcher", icon: "folder.badge.gearshape") {
                Text("Switch active Homebrew prefix between native Apple Silicon ARM64, Rosetta 2 Intel, and custom installations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(prefixManager.availablePrefixes) { prefix in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(prefix.name).font(.subheadline.bold())
                                if prefix.isActive {
                                    Text("Active")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(prefix.brewExecutablePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if prefix.isAvailable {
                            if !prefix.isActive {
                                Button("Switch to Prefix") {
                                    prefixManager.switchPrefix(to: prefix, manager: manager)
                                }
                                .controlSize(.small)
                            }
                        } else {
                            Text("Not Installed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    showingDualArchBridge = true
                } label: {
                    Label("Inspect Dual-Architecture Bridge", systemImage: "cpu.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 4. Snapshots & Brewfile

    private var snapshotsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            MultiMachineSyncView(manager: manager)

            cardSection(title: "Automated Dotfiles & Brewfile Auto-Sync", icon: "arrow.triangle.2.circlepath.circle") {
                Text("Automatically keep your ~/Brewfile or custom dotfiles repository synchronized whenever packages are installed or removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-Sync Brewfile on package operations", isOn: Binding(
                    get: { BrewStoreDotfilesAutoSyncManager.shared.isAutoSyncEnabled },
                    set: { BrewStoreDotfilesAutoSyncManager.shared.isAutoSyncEnabled = $0 }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Brewfile Path").font(.caption.bold())
                    TextField("~/Brewfile or path/to/dotfiles/Brewfile", text: Binding(
                        get: { BrewStoreDotfilesAutoSyncManager.shared.customBrewfilePath },
                        set: { BrewStoreDotfilesAutoSyncManager.shared.customBrewfilePath = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                HStack {
                    if let status = BrewStoreDotfilesAutoSyncManager.shared.lastSyncStatus {
                        Text(status)
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Button("Sync Brewfile Now") {
                        BrewStoreDotfilesAutoSyncManager.shared.syncNow(manager: manager)
                    }
                    .controlSize(.small)
                }
            }

            cardSection(title: "Brewfile Export", icon: "square.and.arrow.up") {
                Text("Export your installed formulae, casks, and taps to a standardized Brewfile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Export Complete Brewfile") {
                        let url = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Documents", isDirectory: true)
                            .appendingPathComponent("Brewfile")
                        manager.exportBrewfile(to: url)
                    }
                    .buttonStyle(.bordered)

                    Button("Export Casks (Apps)") {
                        let url = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Documents", isDirectory: true)
                            .appendingPathComponent("Brewfile-apps")
                        let casks = manager.packages.filter { $0.kind == .cask }
                        manager.exportCustomBrewfile(packages: casks, to: url)
                    }
                    .buttonStyle(.bordered)

                    Button("Export Formulae") {
                        let url = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Documents", isDirectory: true)
                            .appendingPathComponent("Brewfile-formulae")
                        let formulae = manager.packages.filter { $0.kind == .formula }
                        manager.exportCustomBrewfile(packages: formulae, to: url)
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(!manager.isAvailable || manager.isOperating)
            }

            cardSection(title: "Brewfile Import & State Sync", icon: "square.and.arrow.down") {
                Button("Import Brewfile…") { showingBrewfileImporter = true }
                    .disabled(!manager.isAvailable || manager.isOperating)

                if let selectedBrewfileURL {
                    Text("Selected: \(selectedBrewfileURL.lastPathComponent)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !brewfileContents.isEmpty {
                    if let brewfileDiff {
                        BrewfileDiffSummary(diff: brewfileDiff)
                    }
                    TextEditor(text: .constant(brewfileContents))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120, maxHeight: 200)
                        .textSelection(.enabled)

                    Button("Apply Brewfile Changes") { showingBrewfileConfirmation = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.isOperating || selectedBrewfileURL == nil)
                }
                if let brewfileError {
                    Text(brewfileError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }

            cardSection(title: "Time Machine Snapshot Rollback", icon: "clock.arrow.circlepath") {
                HStack {
                    Text("Revert your system packages back to any historical snapshot state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        snapshotManager.createSnapshot(manager: manager)
                    } label: {
                        Label("Create Snapshot Now", systemImage: "camera.fill")
                    }
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }

                if snapshotManager.snapshots.isEmpty {
                    Text("No snapshots saved yet. Snapshots are created automatically before package operations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshotManager.snapshots.prefix(5)) { snap in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Snapshot: \(snap.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.subheadline.bold())
                                Text("\(snap.totalCount) packages recorded")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Rollback to this State") {
                                let plan = rollbackManager.computePlan(currentPackages: manager.packages, snapshot: snap)
                                pendingRollbackPlan = plan
                                showingRollbackConfirmation = true
                            }
                            .controlSize(.small)
                            .disabled(rollbackManager.isRollingBack || manager.isOperating)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - 5. Doctor & Health

    private var doctorSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardSection(title: "Homebrew Doctor Diagnostics", icon: "stethoscope") {
                Text("Inspect your system for missing command tools, unlinked kegs, and configuration conflicts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Run Homebrew Doctor") {
                        manager.runDoctor()
                        showingDoctorSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!manager.isAvailable || manager.isOperating)

                    Spacer()

                    Button("Upgrade All Packages") { showingUpgradeConfirmation = true }
                        .disabled(!manager.isAvailable || manager.isOperating)
                }
            }

            cardSection(title: "Maintenance Tools", icon: "wrench.and.screwdriver") {
                HStack(spacing: 12) {
                    Button("Clean Disk Cache (brew cleanup)") {
                        showingClearCacheConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(!manager.isAvailable || manager.isOperating)
                    .confirmationDialog("Clean Disk Cache?", isPresented: $showingClearCacheConfirm, titleVisibility: .visible) {
                        Button("Run Cleanup (brew cleanup)", role: .destructive) {
                            manager.cleanup()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will run 'brew cleanup' to remove stale lockfiles and outdated download archives for installed formulae and casks.")
                    }

                    Button("Remove Unused Dependencies", role: .destructive) {
                        BrewStoreUninstallCoordinator.shared.requestAutoremove(manager: manager)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!manager.isAvailable || manager.isOperating)
                }
            }
        }
    }

    // MARK: - 6. Storage & Privacy

    // MARK: - Appearance & Theme Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardSection(title: "Custom Accent Themes", icon: "paintbrush.fill") {
                Text("Select an accent color palette that matches your desktop aesthetic.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 10) {
                    ForEach(AppAccentTheme.allCases) { theme in
                        Button {
                            themeManager.currentTheme = theme
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(theme.color).frame(width: 14, height: 14)
                                Text(theme.rawValue).font(.subheadline)
                                Spacer()
                                if themeManager.currentTheme == theme {
                                    Image(systemName: "checkmark").font(.caption.bold())
                                        .foregroundStyle(theme.color)
                                }
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(themeManager.currentTheme == theme ? theme.color : Color.secondary.opacity(0.12), lineWidth: themeManager.currentTheme == theme ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            cardSection(title: "Window Glassmorphism & Vibrancy", icon: "macwindow.on.rectangle") {
                Picker("Vibrancy Material", selection: $themeManager.vibrancyLevel) {
                    ForEach(WindowVibrancyLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text("Adjust macOS window translucency and background vibrancy blending.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            cardSection(title: "Clean Interface & Decluttering", icon: "eye.slash") {
                Toggle("Hide 100% Completed Bundles", isOn: $preferences.hideCompletedBundles)
                Text("Automatically hide developer bundles and toolkits when all contained formulae and casks are installed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Hide Installed Wishlist Items", isOn: $preferences.hideInstalledWishlist)
                Text("Keep your starred wishlist focused on pending tools by hiding packages already installed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Hide In-Sync Snapshots (0 Differences)", isOn: $preferences.hideIdenticalSnapshots)
                Text("Only display snapshots that have differences from your current system state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Storage & Privacy

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            DiskStorageView(manager: manager)

            cardSection(title: "Disk Space Allocation", icon: "internaldrive") {
                LabeledContent("Cellar (Formulae)", value: manager.storageUsage.formattedCellar)
                LabeledContent("Caskroom (Apps)", value: manager.storageUsage.formattedCaskroom)
                LabeledContent("Download Cache", value: manager.storageUsage.formattedCache)
                Divider()
                LabeledContent("Total Disk Usage", value: manager.storageUsage.formattedTotal)

                Button("Recalculate Storage", action: manager.calculateStorageUsage)
                    .controlSize(.small)
            }

            cardSection(title: "Privacy & Analytics Policy", icon: "hand.raised.fill") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                        Text("BrewStore Application: 100% Local & Private").font(.subheadline.bold())
                    }
                    Text("BrewStore does not collect, track, or transmit your searches, installed inventory, or machine identifiers to any remote analytics server.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Homebrew Anonymous Analytics").font(.subheadline.bold())
                            Text("Controls Homebrew's upstream command-line analytics (brew analytics off/on). When enabled, Homebrew sends anonymous usage stats to the Homebrew project.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let isEnabled = manager.isAnalyticsEnabled {
                            Toggle("", isOn: Binding(
                                get: { isEnabled },
                                set: { manager.setAnalytics(enabled: $0) }
                            ))
                            .labelsHidden()
                            .disabled(manager.isOperating)
                        }
                    }
                }
            }

            if !manager.operationHistory.isEmpty {
                cardSection(title: "Operation History", icon: "list.bullet.rectangle") {
                    HStack {
                        Text("\(manager.operationHistory.count) operations recorded").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear History", role: .destructive, action: manager.clearOperationHistory)
                            .controlSize(.small)
                    }

                    ForEach(manager.operationHistory.prefix(8)) { operation in
                        HStack(spacing: 8) {
                            Image(systemName: operation.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(operation.succeeded ? .green : .red)
                            Text(operation.title).font(.caption.bold())
                            Spacer()
                            Text(operation.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            cardSection(title: "Reset & Data Management", icon: "arrow.counterclockwise") {
                Text("Restore specific configurations to default, clear cached Homebrew indexes, or restore application defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    Button("Reset Preferences") {
                        showingResetPreferencesConfirm = true
                    }
                    .controlSize(.small)
                    .confirmationDialog("Reset Preferences?", isPresented: $showingResetPreferencesConfirm, titleVisibility: .visible) {
                        Button("Reset Preferences", role: .destructive) {
                            resetManager.resetPreferences()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will revert all application settings and toggles to their default values.")
                    }

                    Button("Clear Catalog Cache") {
                        showingClearCacheConfirm = true
                    }
                    .controlSize(.small)
                    .confirmationDialog("Clear Catalog Cache?", isPresented: $showingClearCacheConfirm, titleVisibility: .visible) {
                        Button("Clear Cache", role: .destructive) {
                            resetManager.resetDiscoveryCache(discovery: discovery)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete local cached formula and cask indexes and re-fetch them from the official Homebrew catalog.")
                    }

                    Button("Reset Wishlist") {
                        BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.unstarEverything]) {
                            resetManager.resetWishlist()
                        }
                    }
                    .controlSize(.small)

                    Button("Reset Version Pins") {
                        BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.unpinEverything]) {
                            resetManager.resetPinnedPackages(manager: manager)
                        }
                    }
                    .controlSize(.small)

                    Button("Clear Logs & History") {
                        BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.cleanupEverything]) {
                            resetManager.resetHistoryAndLogs(manager: manager)
                        }
                    }
                    .controlSize(.small)

                    Button("Reset Appearance") {
                        BrewStoreActionReviewCoordinator.shared.requestSettingsReset(options: [.clearPersonalSettings]) {
                            resetManager.resetThemeAndAppearance()
                        }
                    }
                    .controlSize(.small)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore App Defaults").font(.subheadline.bold())
                        Text("Reverts interface preferences and local caches back to initial defaults.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset Everything…", role: .destructive) {
                        resetManager.showingResetSheet = true
                    }
                    .controlSize(.regular)
                }
            }
        }
    }

    // MARK: - Reusable Card Section

    private func cardSection(title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                Text(title).font(.headline)
            }
            Divider()
            content()
        }
        .padding(16)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func formatRefreshInterval(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds % 60 == 0 {
            let mins = seconds / 60
            return "\(mins) min\(mins == 1 ? "" : "s")"
        } else {
            let mins = seconds / 60
            let rem = seconds % 60
            return "\(mins)m \(rem)s"
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

private struct DoctorDiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let diagnostics: [BrewStoreDoctorDiagnostic]
    @State private var copiedCommand: String?
    @State private var showingAutoFixConfirmation = false

    private var fixableDiagnostics: [BrewStoreDoctorDiagnostic] {
        diagnostics.filter { $0.isAutoFixable && $0.autoFixCommand != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Homebrew Doctor").font(.title2.bold())
                    Text("Diagnostics and system configuration repair.").foregroundStyle(.secondary)
                }
                Spacer()

                if !fixableDiagnostics.isEmpty {
                    Button("Auto-Fix Issues (\(fixableDiagnostics.count))") {
                        showingAutoFixConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isOperating)
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }

            if manager.isOperating {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(manager.activeOperationTitle ?? "Running Homebrew Doctor…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
            } else if diagnostics.isEmpty {
                ContentUnavailableView("No Diagnostic Results", systemImage: "stethoscope", description: Text("Run Homebrew Doctor to inspect system health."))
            } else {
                List(diagnostics) { diag in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: diag.severity == .clean ? "checkmark.circle.fill" : (diag.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"))
                                .foregroundStyle(diag.severity == .clean ? .green : (diag.severity == .error ? .red : .orange))
                            Text(diag.title).font(.headline)
                            Spacer()

                            if diag.isAutoFixable {
                                Text("Auto-Fixable")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.green)
                            } else if diag.requiresSudo {
                                Text("Terminal / Sudo")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }

                            Text(diag.severity.rawValue)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(diag.severity == .clean ? Color.green.opacity(0.12) : Color.orange.opacity(0.12), in: Capsule())
                                .foregroundStyle(diag.severity == .clean ? .green : .orange)
                        }

                        Text(diag.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        if let cmd = diag.suggestedCommand {
                            HStack {
                                Text(cmd)
                                    .font(.caption.monospaced())
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    .textSelection(.enabled)
                                Spacer()

                                if diag.isAutoFixable {
                                    Button("Fix Now") {
                                        manager.applyDoctorFixes(diagnostics: [diag])
                                    }
                                    .controlSize(.small)
                                    .disabled(manager.isOperating)
                                }

                                Button(copiedCommand == cmd ? "Copied!" : "Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(cmd, forType: .string)
                                    copiedCommand = cmd
                                }
                                .controlSize(.small)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
        .confirmationDialog("Apply Auto-Fixes?", isPresented: $showingAutoFixConfirmation, titleVisibility: .visible) {
            Button("Apply \(fixableDiagnostics.count) Repairs", role: .none) {
                manager.applyDoctorFixes(diagnostics: fixableDiagnostics)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("BrewStore will execute safe Homebrew repair commands sequentially.")
        }
    }
}

private struct BrewfileDiffSummary: View {
    let diff: BrewStoreBrewfileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Planned changes: \(diff.changeCount)").font(.headline)
            if !diff.missingFormulae.isEmpty {
                Text("Install formulae: \(diff.missingFormulae.joined(separator: ", "))")
            }
            if !diff.missingCasks.isEmpty {
                Text("Install casks: \(diff.missingCasks.joined(separator: ", "))")
            }
            if !diff.missingTaps.isEmpty {
                Text("Add taps: \(diff.missingTaps.joined(separator: ", "))")
            }
            if diff.changeCount == 0 {
                Text("Everything in this Brewfile is already present.").foregroundStyle(.secondary)
            }
            if !diff.extraInstalledFormulae.isEmpty || !diff.extraInstalledCasks.isEmpty {
                Text("Existing packages not listed here will be left unchanged.").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .textSelection(.enabled)
    }
}
