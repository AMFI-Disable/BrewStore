import AppKit
import SwiftUI

enum MenuBarTab: String, CaseIterable, Identifiable {
    case updates = "Updates"
    case services = "Services"
    case tools = "Tools"

    var id: String {
        rawValue
    }
}

@MainActor
struct MenuBarExtraView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var updateMonitor: BrewStoreUpdateMonitor
    @ObservedObject var preferences = BrewStorePreferences.shared
    @StateObject private var serviceTelemetry = BrewStoreServiceTelemetryMonitor()
    @State private var selectedTab: MenuBarTab = .updates

    private func presentMainWindow() {
        openWindow(id: "main")
        BrewStoreDockLifecycleManager.shared.showMainWindowAndDock()
        BrewStoreMenuBarCompanionManager.shared.closeMenuBarPanel()
    }
    private var outdatedPackages: [BrewStorePackage] {
        manager.packages.filter(\.isOutdated)
    }

    private var runningServices: [BrewStoreService] {
        manager.services.filter(\.isRunning)
    }

    private var rosettaCount: Int {
        BrewStoreAppleSiliconMigrationManager.shared.report?.rosettaIntelCount ?? 0
    }

    private var scrollAreaHeight: CGFloat {
        let totalHeight = preferences.compactMenuBarView ?
            BrewStoreMenuBarCompanionManager.compactPanelHeight :
            BrewStoreMenuBarCompanionManager.panelHeight
        return totalHeight - 127
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (Rigid 48pt height prevents window jumps)
            HStack(spacing: 10) {
                Image("menubar_mug", bundle: .main)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("BrewStore")
                        .font(.headline)
                        .lineLimit(1)
                    Text(manager.brewPrefix ?? (manager.isAvailable ? "Homebrew Active" : "Not Connected"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if rosettaCount > 0 {
                    Button {
                        presentMainWindow()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                            Text("\(rosettaCount) Intel")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("\(rosettaCount) Intel apps running under Rosetta 2 emulation. Click to inspect.")
                    .accessibilityLabel("\(rosettaCount) Intel apps running under Rosetta 2 emulation")
                    .accessibilityHint("Click to open BrewStore and inspect native migration")
                }

                // Stable trailing status/action area
                HStack(spacing: 6) {
                    if manager.isOperating {
                        ProgressView()
                            .controlSize(.mini)
                        if let liveRemaining = BrewStoreUpdateEstimator.liveRemainingTimeString(manager: manager) {
                            Text(liveRemaining)
                                .font(.caption2.bold())
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                        }
                    } else {
                        Button {
                            manager.refresh()
                            if preferences.menuBarCloseOnAction {
                                BrewStoreMenuBarCompanionManager.shared.closeMenuBarPanel()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh Homebrew")
                        .accessibilityLabel("Refresh Homebrew")
                    }
                }
                .frame(width: 110, height: 26, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(width: BrewStoreMenuBarCompanionManager.panelWidth, height: 48)
            .background(Color.secondary.opacity(0.06))

            Divider()

            // 3-Tab Segment (Rigid height & full width, fixed titles prevent shift)
            Picker("", selection: $selectedTab) {
                Text("Updates").tag(MenuBarTab.updates)
                Text("Services").tag(MenuBarTab.services)
                Text("Tools").tag(MenuBarTab.tools)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: BrewStoreMenuBarCompanionManager.panelWidth, height: 40)

            Divider()

            // Tab Content fills exact remaining space with tab-isolated scroll offset and no shifting
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    switch selectedTab {
                    case .updates:
                        updatesTabContent
                    case .services:
                        servicesTabContent
                    case .tools:
                        toolsTabContent
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .id(selectedTab)
            .animation(nil, value: selectedTab)
            .frame(width: BrewStoreMenuBarCompanionManager.panelWidth, height: scrollAreaHeight)

            Divider()

            // Footer (Rigid 36pt height)
            HStack {
                Button("Open BrewStore") {
                    presentMainWindow()
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(width: BrewStoreMenuBarCompanionManager.panelWidth, height: 36)
        }
        .frame(
            width: BrewStoreMenuBarCompanionManager.panelWidth,
            height: preferences.compactMenuBarView ?
                BrewStoreMenuBarCompanionManager.compactPanelHeight :
                BrewStoreMenuBarCompanionManager.panelHeight
        )
        .background(MenuBarPanelWindowAccessor(isCompact: preferences.compactMenuBarView))
        .onAppear {
            if let tab = MenuBarTab(rawValue: preferences.defaultMenuBarTab) {
                selectedTab = tab
            }
            serviceTelemetry.refreshTelemetry(for: manager.services)
        }
    }

    // MARK: - Updates Tab

    @ViewBuilder
    private var updatesTabContent: some View {
        if outdatedPackages.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("All Packages Up to Date")
                    .font(.caption.bold())
                Text("No pending formula or cask updates.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else {
            let totalEstimate = BrewStoreUpdateEstimator.estimate(for: outdatedPackages)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)

                    if let liveRemaining = BrewStoreUpdateEstimator.liveRemainingTimeString(manager: manager) {
                        Text("Updating: \(liveRemaining)")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    } else {
                        Text("Est. total time: ~\(totalEstimate.formattedEstimate)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(outdatedPackages.count) pending")
                        .font(.caption2.bold().monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                        .foregroundStyle(.orange)
                }
                .frame(height: 20)
                .padding(.horizontal, 4)

                ForEach(outdatedPackages.prefix(8)) { pkg in
                    MenuBarOutdatedRow(
                        manager: manager,
                        package: pkg,
                        preferences: preferences
                    )
                }

                if outdatedPackages.count > 1 {
                    Button {
                        manager.upgradeAllPackages()
                        if preferences.menuBarCloseOnAction {
                            BrewStoreMenuBarCompanionManager.shared.closeMenuBarPanel()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Spacer()
                            if manager.isOperating {
                                ProgressView().controlSize(.mini)
                                Text(BrewStoreUpdateEstimator.liveRemainingTimeString(manager: manager) ?? "Updating All…")
                                    .font(.caption.bold())
                                    .lineLimit(1)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption.bold())
                                Text("Update All (\(outdatedPackages.count)) · ~\(totalEstimate.formattedEstimate)")
                                    .font(.caption.bold())
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
                    .disabled(manager.isOperating)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Services Tab

    @ViewBuilder
    private var servicesTabContent: some View {
        if manager.services.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "gearshape.2")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No Background Services")
                    .font(.caption.bold())
                Text("No Homebrew services are currently configured.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text("Background Daemons")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(runningServices.count) running")
                        .font(.caption2.bold().monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .foregroundStyle(.green)
                }
                .frame(height: 20)
                .padding(.horizontal, 4)

                ForEach(manager.services) { svc in
                    MenuBarServiceRow(
                        manager: manager,
                        service: svc,
                        metric: serviceTelemetry.metrics[svc.name],
                        preferences: preferences
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Tools Tab

    private var toolsTabContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            menuBarToolRow(
                title: "Fetch Homebrew Updates (brew update)",
                icon: "arrow.triangle.2.circlepath"
            ) {
                manager.updateHomebrew()
                if preferences.menuBarCloseOnAction {
                    BrewStoreMenuBarCompanionManager.shared.closeMenuBarPanel()
                }
            }

            menuBarToolRow(
                title: "Deep Clean All Caches",
                icon: "trash.fill"
            ) {
                BrewStoreDiskStorageAnalyzerManager.shared.purgeCache(manager: manager)
                BrewStoreDeveloperCacheManager.shared.purgeSelected()
                if preferences.menuBarCloseOnAction {
                    BrewStoreMenuBarCompanionManager.shared.closeMenuBarPanel()
                }
            }

            menuBarToolRow(
                title: "Repair Common Issues",
                icon: "wrench.and.screwdriver.fill"
            ) {
                BrewStoreDependencyDoctorManager.shared.autoHealToolchain(manager: manager)
                if preferences.menuBarCloseOnAction {
                    BrewStoreMenuBarCompanionManager.shared.closeMenuBarPanel()
                }
            }

            menuBarToolRow(
                title: "Remove Unused Dependencies",
                icon: "scissors"
            ) {
                presentMainWindow()
                BrewStoreUninstallCoordinator.shared.requestAutoremove(manager: manager)
            }

            if rosettaCount > 0 {
                menuBarToolRow(
                    title: "Migrate \(rosettaCount) Intel Apps to Native ARM64",
                    icon: "cpu"
                ) {
                    BrewStoreAppleSiliconMigrationManager.shared.migrateAllRosettaPackages(manager: manager)
                    if preferences.menuBarCloseOnAction {
                        BrewStoreMenuBarCompanionManager.shared.closeMenuBarPanel()
                    }
                }
            }

            menuBarToolRow(
                title: "Open Full Application",
                icon: "arrow.up.forward.app"
            ) {
                presentMainWindow()
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func menuBarToolRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .frame(width: 16)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(manager.isOperating)
    }
}

// MARK: - Outdated Row

private struct MenuBarOutdatedRow: View {
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage
    let preferences: BrewStorePreferences

    var body: some View {
        let pkgEstimate = BrewStoreUpdateEstimator.estimate(for: package)
        HStack(spacing: 8) {
            Image(systemName: package.kind == .cask ? "app.fill" : "terminal.fill")
                .font(.caption)
                .foregroundStyle(package.kind == .cask ? Color.blue : Color.green)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(package.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(package.version)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("~\(pkgEstimate.formattedEstimate)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button("Update") {
                manager.perform(package: package, action: .upgrade)
                if preferences.menuBarCloseOnAction {
                    BrewStoreMenuBarCompanionManager.shared.closeMenuBarPanel()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .frame(width: 58)
            .disabled(manager.isOperating)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Service Row

private struct MenuBarServiceRow: View {
    @ObservedObject var manager: HomebrewManager
    let service: BrewStoreService
    let metric: ServiceProcessMetrics?
    let preferences: BrewStorePreferences

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(service.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(service.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                    if service.isRunning, let port = metric?.listeningPort {
                        Text(":\(port)")
                            .font(.system(size: 9, design: .monospaced).bold())
                            .foregroundStyle(.blue)
                    }
                }
                if service.isRunning {
                    HStack(spacing: 6) {
                        if let cpu = metric?.formattedCPU {
                            Text("CPU \(cpu)")
                                .font(.system(size: 8).monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if let ram = metric?.formattedRAM {
                            Text("RAM \(ram)")
                                .font(.system(size: 8).monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Stopped")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(service.isRunning ? "Stop" : "Start") {
                manager.perform(service: service, action: service.isRunning ? .stop : .start)
                if preferences.menuBarCloseOnAction {
                    BrewStoreMenuBarCompanionManager.shared.closeMenuBarPanel()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .frame(width: 54)
            .disabled(manager.isOperating)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Menu Bar Panel Window Accessor (Disables Resize Animations and Enforces Rigid Frame)

private struct MenuBarPanelWindowAccessor: NSViewRepresentable {
    let isCompact: Bool

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                BrewStoreMenuBarCompanionManager.shared.configureMenuBarWindow(window, isCompact: isCompact)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        if let window = nsView.window {
            let targetHeight = isCompact ?
                BrewStoreMenuBarCompanionManager.compactPanelHeight :
                BrewStoreMenuBarCompanionManager.panelHeight
            let widthDiff = abs(window.frame.width - BrewStoreMenuBarCompanionManager.panelWidth)
            let heightDiff = abs(window.frame.height - targetHeight)
            if widthDiff > 1.0 || heightDiff > 1.0 {
                BrewStoreMenuBarCompanionManager.shared.configureMenuBarWindow(window, isCompact: isCompact)
            }
        }
    }
}
