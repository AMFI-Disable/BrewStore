import AppKit
import SwiftUI

enum EnvironmentSubMode: String, CaseIterable, Identifiable {
    case services = "Services"
    case taps = "Taps"
    case creator = "Creator Studio"

    var id: String {
        rawValue
    }

    var section: BrewStoreSection {
        switch self {
        case .services: .services
        case .taps: .taps
        case .creator: .creator
        }
    }

    init?(section: BrewStoreSection) {
        switch section {
        case .services: self = .services
        case .taps: self = .taps
        case .creator: self = .creator
        default: return nil
        }
    }
}

struct EnvironmentHubView: View {
    @ObservedObject var manager: HomebrewManager
    @Binding var selection: BrewStoreSection?
    @ObservedObject var accountManager: GitHubAccountManager

    @State private var subMode: EnvironmentSubMode = .services
    @State private var showingVersionSwitcher = false
    @State private var showingShellProfiler = false
    @State private var showingDualArchBridge = false
    @State private var showingOrphanAndKegAuditor = false
    @State private var showingBottleIntegrityAuditor = false

    private var runningServicesCount: Int {
        manager.services.filter(\.isRunning).count
    }

    private var erroredServicesCount: Int {
        manager.services.filter(\.isError).count
    }

    private var tapsCount: Int {
        manager.taps.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // ZONE 1: Hub Header & Anchor Controls
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            Text("Developer Environment")
                                .font(.title2.bold())
                        }
                        Text("Manage background services, custom third-party taps, and package creation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Zone 1 Primary Contextual Action
                    HStack(spacing: 8) {
                        if subMode == .services, erroredServicesCount > 0 {
                            Button {
                                let errored = manager.services.filter(\.isError)
                                manager.batchPerform(services: errored, action: .restart)
                            } label: {
                                Label("Restart Failed (\(erroredServicesCount))", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(manager.isOperating)
                        }

                        Button {
                            showingVersionSwitcher = true
                        } label: {
                            Label("Version Switcher", systemImage: "arrow.triangle.swap")
                        }
                        .controlSize(.small)

                        Button(action: manager.refresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(manager.isLoading || manager.isOperating)
                    }
                }

                // Zone 1: Segmented Switcher
                HStack {
                    Picker("Environment Navigation", selection: $subMode) {
                        HStack(spacing: 4) {
                            Text("Background Services")
                            if runningServicesCount > 0 {
                                Text("(\(runningServicesCount) running)")
                                    .bold()
                            }
                        }.tag(EnvironmentSubMode.services)

                        Text("Custom Taps (\(tapsCount))").tag(EnvironmentSubMode.taps)
                        Text("Creator Studio").tag(EnvironmentSubMode.creator)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: subMode) { _, newMode in
                        if selection != newMode.section {
                            selection = newMode.section
                        }
                    }

                    Spacer()

                    Button {
                        showingShellProfiler = true
                    } label: {
                        Label("Profile Shell", systemImage: "gauge.with.needle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showingDualArchBridge = true
                    } label: {
                        Label("Dual-Arch Bridge", systemImage: "cpu")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showingOrphanAndKegAuditor = true
                    } label: {
                        Label("Orphans & Keg-Only", systemImage: "leaf.arrow.triangle.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showingBottleIntegrityAuditor = true
                    } label: {
                        Label("Bottle Integrity", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ToolchainCompanionsCard(manager: manager)
                    .padding(.top, 4)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.sm)

            Divider()

            // ZONE 3: Primary Content Canvas
            Group {
                switch subMode {
                case .services:
                    ServicesView(manager: manager, showHeader: false)
                case .taps:
                    TapsView(manager: manager, showHeader: false)
                case .creator:
                    CreatorStudioView(manager: manager, accountManager: accountManager, showHeader: false)
                }
            }
            .id(subMode)
            .animation(nil, value: subMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingVersionSwitcher) {
            VersionLinkView(manager: manager)
        }
        .sheet(isPresented: $showingShellProfiler) {
            ShellProfilerView()
        }
        .sheet(isPresented: $showingDualArchBridge) {
            DualArchitectureBridgeView(manager: manager)
        }
        .sheet(isPresented: $showingOrphanAndKegAuditor) {
            OrphanAndKegAuditorView(manager: manager)
        }
        .sheet(isPresented: $showingBottleIntegrityAuditor) {
            BottleIntegrityAuditorView(manager: manager)
        }
        .onAppear {
            syncFromSelection()
        }
        .onChange(of: selection) { _, _ in
            syncFromSelection()
        }
    }

    private func syncFromSelection() {
        if let current = selection, let mapped = EnvironmentSubMode(section: current) {
            if subMode != mapped {
                subMode = mapped
            }
        }
    }
}

// MARK: - Toolchain & Companions Status Card Model

struct ToolchainCompanionItem: Identifiable, Equatable {
    let id: String
    let name: String
    let formulaName: String
    let category: String
    let icon: String
    let description: String
    let isInstalled: Bool
    let binaryPath: String?
    let detailStatus: String
    let canInstall: Bool
}

@MainActor
final class ToolchainCompanionsModel: ObservableObject {
    @Published var items: [ToolchainCompanionItem] = []
    @Published var isDetecting: Bool = false
    @Published var installingItemID: String?

    func refresh(speedTestManager: BrewStoreSpeedTestManager? = nil, masManager: BrewStoreMASManager? = nil) {
        let speedTest = speedTestManager ?? .shared
        let mas = masManager ?? .shared
        speedTest.detectBinary()
        mas.checkMASAvailability()

        var list: [ToolchainCompanionItem] = []

        // 1. speedtest-go (Live download speed & ETA calculation)
        let speedInstalled = speedTest.isAvailable
        let speedDetail: String = if speedInstalled {
            if speedTest.currentDownloadSpeedMbps != nil {
                speedTest.formattedSpeed
            } else {
                "Ready (Live ETA active)"
            }
        } else {
            "Missing (Heuristic ETA)"
        }
        list.append(ToolchainCompanionItem(
            id: "speedtest-go",
            name: "speedtest-go",
            formulaName: "speedtest-go",
            category: "Bandwidth & ETA",
            icon: "speedometer",
            description: "Measures real-time download bandwidth to calculate precise package installation ETAs.",
            isInstalled: speedInstalled,
            binaryPath: speedTest.binaryPath,
            detailStatus: speedDetail,
            canInstall: !speedInstalled
        ))

        // 2. mas-cli (Mac App Store package management)
        let masInstalled = mas.isMASInstalled
        let masDetail: String
        if masInstalled {
            let count = mas.installedApps.count
            masDetail = count > 0 ? "\(count) MAS apps tracked" : "Ready (CLI active)"
        } else {
            masDetail = "Missing (App Store off)"
        }
        list.append(ToolchainCompanionItem(
            id: "mas",
            name: "mas-cli",
            formulaName: "mas",
            category: "App Store CLI",
            icon: "apple.logo",
            description: "Scans, inspects, and upgrades Mac App Store applications alongside Homebrew casks.",
            isInstalled: masInstalled,
            binaryPath: mas.masBinaryPath,
            detailStatus: masDetail,
            canInstall: !masInstalled
        ))

        // 3. Safe Trash Engine & CLI
        let trashPath = detectTrashBinary()
        let trashInstalled = trashPath != nil
        list.append(ToolchainCompanionItem(
            id: "trash",
            name: "trash",
            formulaName: "trash",
            category: "Safe File Deletion",
            icon: "trash.fill",
            description: "Safely moves uninstalled apps, bottles, and caches to macOS Trash instead of permanent rm.",
            isInstalled: trashInstalled,
            binaryPath: trashPath,
            detailStatus: trashInstalled ? "Active (CLI & Native Trash)" : "Active (Native Foundation Trash)",
            canInstall: !trashInstalled
        ))

        // 4. Xcode Command Line Tools & Git
        let gitPath = detectGitBinary()
        let cltInstalled = detectCLTInstalled()
        let gitInstalled = gitPath != nil
        list.append(ToolchainCompanionItem(
            id: "git",
            name: "git",
            formulaName: "git",
            category: "Developer Toolchain & Git",
            icon: "arrow.triangle.branch",
            description: "Core developer toolchain and version control powering taps, formula builds, and cloud backups.",
            isInstalled: gitInstalled,
            binaryPath: gitPath,
            detailStatus: cltInstalled ? "Active (Xcode CLT & Git)" : (gitInstalled ? "Active (System Git)" : "Missing (CLT recommended)"),
            canInstall: false
        ))

        // 5. mole (Optional community cleanup utility)
        let moleManager = BrewStoreMoleManager.shared
        moleManager.detectBinary()
        let moleInstalled = moleManager.isAvailable
        let moleDetail = moleInstalled ? "Installed (Optional CLI)" : "Not Installed (Native engine active)"
        list.append(ToolchainCompanionItem(
            id: "mole",
            name: "mole (mo)",
            formulaName: "mole",
            category: "Optional Cleanup Utility",
            icon: "sparkles.rectangle.stack.fill",
            description: "Optional third-party cleanup utility. BrewStore uses native macOS Trash and Homebrew zap by default.",
            isInstalled: moleInstalled,
            binaryPath: moleManager.binaryPath,
            detailStatus: moleDetail,
            canInstall: !moleInstalled
        ))

        self.items = list
    }

    private func detectTrashBinary() -> String? {
        let candidates = ["/opt/homebrew/bin/trash", "/usr/local/bin/trash", "~/.local/bin/trash"]
        for p in candidates {
            let expanded = NSString(string: p).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let cand = URL(fileURLWithPath: String(dir)).appendingPathComponent("trash").path
            if FileManager.default.isExecutableFile(atPath: cand) {
                return cand
            }
        }
        return nil
    }

    private func detectGitBinary() -> String? {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        for p in candidates {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }

    private func detectCLTInstalled() -> Bool {
        let candidates = [
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Library/Developer/CommandLineTools",
            "/Applications/Xcode.app"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }

    func install(item: ToolchainCompanionItem, manager: HomebrewManager, completion: ((Bool) -> Void)? = nil) {
        installingItemID = item.id
        let handleCompletion: (Bool) -> Void = { [weak self] success in
            Task { @MainActor in
                self?.installingItemID = nil
                self?.refresh()
                completion?(success)
            }
        }

        switch item.id {
        case "speedtest-go":
            BrewStoreSpeedTestManager.shared.installSpeedTest(manager: manager, completion: handleCompletion)
        case "mas":
            BrewStoreMASManager.shared.installMAS(manager: manager, completion: handleCompletion)
        case "mole":
            BrewStoreMoleManager.shared.installMole(manager: manager, completion: handleCompletion)
        case "trash":
            let pkg = BrewStorePackage(
                id: "trash",
                name: "trash",
                description: "Move files and folders to the trash",
                homepage: "https://hasseg.org/trash/",
                version: "latest",
                kind: .formula
            )
            manager.perform(package: pkg, action: .install, completion: handleCompletion)
        default:
            installingItemID = nil
            completion?(false)
        }
    }

    func installAllMissing(manager: HomebrewManager) {
        let missing = items.filter { !$0.isInstalled && $0.canInstall }
        guard !missing.isEmpty else { return }

        func installNext(_ queue: [ToolchainCompanionItem]) {
            guard let next = queue.first else {
                self.installingItemID = nil
                self.refresh()
                return
            }
            install(item: next, manager: manager) { _ in
                installNext(Array(queue.dropFirst()))
            }
        }
        installNext(missing)
    }
}

// MARK: - Toolchain & Companions Status Card View

struct ToolchainCompanionsCard: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var model = ToolchainCompanionsModel()
    @ObservedObject private var speedTestManager = BrewStoreSpeedTestManager.shared
    @ObservedObject private var masManager = BrewStoreMASManager.shared
    @ObservedObject private var moleManager = BrewStoreMoleManager.shared
    @AppStorage("Environment.CompanionsCard.isExpanded") private var isExpanded: Bool = true

    private var missingCount: Int {
        model.items.filter { !$0.isInstalled && $0.canInstall }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card Header Bar
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)

                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text("Companions & Dependencies")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)

                                if missingCount == 0 {
                                    HStack(spacing: 3) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 9))
                                        Text("All Active")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                } else {
                                    HStack(spacing: 3) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 9))
                                        Text("\(missingCount) Missing")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                            }

                            Text("Core CLI dependencies that power live speed measurement, App Store sync, and safe trash.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if missingCount > 0 {
                    Button {
                        model.installAllMissing(manager: manager)
                    } label: {
                        Label("Install Missing", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }
            }

            // Expanded Grid of Companions
            if isExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 8)], spacing: 8) {
                    ForEach(model.items) { item in
                        companionItemTile(item)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
        .onAppear {
            model.refresh(speedTestManager: speedTestManager, masManager: masManager)
        }
        .onChange(of: manager.isOperating) { _, isOp in
            if !isOp {
                model.refresh(speedTestManager: speedTestManager, masManager: masManager)
            }
        }
        .onChange(of: moleManager.isAvailable) { _, _ in
            model.refresh(speedTestManager: speedTestManager, masManager: masManager)
        }
    }

    private func companionItemTile(_ item: ToolchainCompanionItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.isInstalled ? Color.accentColor : .secondary)
                    .frame(width: 14)

                Text(item.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(item.category)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }

            Text(item.description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 4) {
                Circle()
                    .fill(item.isInstalled ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)

                Text(item.detailStatus)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(item.isInstalled ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if !item.isInstalled, item.canInstall {
                    Button("Install") {
                        model.install(item: item, manager: manager)
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isOperating)
                } else if item.isInstalled {
                    if item.id == "speedtest-go" {
                        Button {
                            speedTestManager.runSpeedTest(force: true)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: speedTestManager.isRunningTest ? "hourglass" : "play.fill")
                                    .font(.system(size: 7))
                                Text("Test")
                                    .font(.system(size: 9))
                            }
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                        .disabled(speedTestManager.isRunningTest)
                        .help("Run live speedtest")
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.trailing, 2)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5))
    }
}
