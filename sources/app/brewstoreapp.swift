import AppKit
import SwiftUI

final class BrewStoreAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        BrewStoreDockLifecycleManager.shared.setup()

        // SwiftUI creates the WindowGroup after the app delegate callback.
        // Reveal it on the next run-loop turn so a menu-bar-only launch does
        // not leave the primary application window hidden at startup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            BrewStoreDockLifecycleManager.shared.showMainWindowAndDock()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            BrewStoreDockLifecycleManager.shared.showMainWindowAndDock()
        }
        return true
    }
}

@main
struct BrewStoreApp: App {
    @NSApplicationDelegateAdaptor(BrewStoreAppDelegate.self) private var appDelegate

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil ||
            NSClassFromString("XCTestCase") != nil
    }

    @StateObject private var manager = HomebrewManager()
    @StateObject private var discovery = BrewStoreDiscoveryCatalog()
    @StateObject private var updateMonitor = BrewStoreUpdateMonitor()
    @ObservedObject private var preferences = BrewStorePreferences.shared

    @State private var selection: BrewStoreSection? = .discover
    @State private var showingCommandPalette = false
    @State private var showingHelpSheet = false

    var body: some Scene {
        WindowGroup(id: "main") {
            if Self.isRunningTests {
                Text("Running Unit Tests…")
            } else {
                BrewStoreRootView(
                    manager: manager,
                    discovery: discovery,
                    updateMonitor: updateMonitor,
                    selection: $selection,
                    showingCommandPalette: $showingCommandPalette,
                    showingHelpSheet: $showingHelpSheet
                )
                .frame(minWidth: 860, minHeight: 560)
                .background(BrewStoreWindowAccessor())
                .onAppear {
                    updateMonitor.setManager(manager)
                }
            }
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            if !Self.isRunningTests {
                BrewStoreCommands(
                    manager: manager,
                    discovery: discovery,
                    selection: $selection,
                    showingCommandPalette: $showingCommandPalette,
                    showingHelpSheet: $showingHelpSheet
                )
            }
        }

        MenuBarExtra {
            if !Self.isRunningTests {
                MenuBarExtraView(manager: manager, updateMonitor: updateMonitor)
            }
        } label: {
            let outdatedCount = manager.packages.filter(\.isOutdated).count
            let style = preferences.menuBarBadgeStyle

            HStack(spacing: 3) {
                Image("menubar_mug", bundle: .main)
                    .renderingMode(.template)

                if outdatedCount > 0, preferences.showMenuBarBadge {
                    if style == "count" {
                        Text("\(outdatedCount)")
                            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                            .frame(minWidth: 10)
                    } else if style == "dot" {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct BrewStoreCommands: Commands {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var discovery: BrewStoreDiscoveryCatalog
    @Binding var selection: BrewStoreSection?
    @Binding var showingCommandPalette: Bool
    @Binding var showingHelpSheet: Bool

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for BrewStore Updates…") {
                selection = .settings
                BrewStoreAppUpdateChecker.shared.checkForAppUpdates()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Quick Open…") {
                showingCommandPalette = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button("Import Brewfile…") {
                selection = .settings
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Export Brewfile…") {
                selection = .settings
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        CommandMenu("Navigate") {
            Button("Discover") { selection = .discover }
                .keyboardShortcut("1", modifiers: .command)
            Button("Community Picks") { selection = .showdown }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Stories") { selection = .stories }
                .keyboardShortcut("2", modifiers: .command)
            Button("Toolkits") { selection = .toolkits }
                .keyboardShortcut("3", modifiers: .command)
            Button("Categories") { selection = .categories }
                .keyboardShortcut("4", modifiers: .command)
            Button("Installed") { selection = .installed }
                .keyboardShortcut("5", modifiers: .command)
            Button("Adoption & Replacements") { selection = .adoption }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Dependencies") { selection = .topology }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Wishlist") { selection = .wishlist }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Updates") { selection = .updates }
                .keyboardShortcut("6", modifiers: .command)
            Button("Services") { selection = .services }
                .keyboardShortcut("7", modifiers: .command)
            Button("Taps") { selection = .taps }
                .keyboardShortcut("8", modifiers: .command)
            Button("Creator Studio") { selection = .creator }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Backups") { selection = .backups }
                .keyboardShortcut("9", modifiers: .command)
            Button("Settings") { selection = .settings }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Settings (Preferences)") { selection = .settings }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Refresh All") {
                if manager.isAvailable {
                    manager.retryRefresh()
                }
                discovery.load(force: true)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(manager.isLoading || manager.isOperating)
        }

        CommandMenu("Topology") {
            Button("Shared Foundations") {
                selection = .topology
                BrewStoreDependencyTopologyManager.shared.selectedTab = .foundations
            }
            .keyboardShortcut("1", modifiers: [.command, .control])

            Button("Orphan Leaves") {
                selection = .topology
                BrewStoreDependencyTopologyManager.shared.selectedTab = .orphans
            }
            .keyboardShortcut("2", modifiers: [.command, .control])

            Button("Integrity & Linkage") {
                selection = .topology
                BrewStoreDependencyTopologyManager.shared.selectedTab = .integrity
            }
            .keyboardShortcut("3", modifiers: [.command, .control])

            Divider()

            Button("Re-Analyze Topology") {
                selection = .topology
                BrewStoreDependencyTopologyManager.shared.analyzeTopology(manager: manager)
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(BrewStoreDependencyTopologyManager.shared.isAnalyzing || manager.isOperating)
        }

        CommandMenu("Maintenance") {
            Button("Upgrade All Outdated Packages") {
                let outdated = manager.packages.filter(\.isOutdated)
                if !outdated.isEmpty {
                    BrewStoreActionReviewCoordinator.shared.requestUpgrade(packages: outdated, manager: manager) {
                        manager.upgradeAllPackages()
                    }
                } else {
                    manager.upgradeAllPackages()
                }
            }
            .keyboardShortcut("u", modifiers: [.command, .option])
            .disabled(!manager.isAvailable || manager.isOperating)

            Button("Fetch Latest Metadata (brew update)") {
                manager.updateHomebrew()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!manager.isAvailable || manager.isOperating)

            Button("Clean Disk Cache (brew cleanup)") {
                manager.cleanup()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])
            .disabled(!manager.isAvailable || manager.isOperating)

            Button("Remove Unused Dependencies (brew autoremove)") {
                BrewStoreUninstallCoordinator.shared.requestAutoremove(manager: manager)
            }
            .disabled(!manager.isAvailable || manager.isOperating)

            Divider()

            Button("Run Homebrew Doctor Diagnostics") {
                selection = .settings
                manager.runDoctor()
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(!manager.isAvailable || manager.isOperating)

            Divider()

            Button("Reset BrewStore Data…") {
                selection = .settings
                BrewStoreResetManager.shared.showingResetSheet = true
            }
        }

        CommandGroup(replacing: .help) {
            Button("BrewStore Help Manual") {
                showingHelpSheet = true
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button("Homebrew Documentation") {
                if let url = URL(string: "https://docs.brew.sh") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Report an Issue on GitHub") {
                if let url = URL(string: "https://github.com/Homebrew/brew/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

private struct BrewStoreWindowAccessor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        WindowTrackingView()
    }

    func updateNSView(_: NSView, context _: Context) {}
}

private final class WindowTrackingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        BrewStoreWindowFrameManager.shared.attach(to: window)
    }
}
