import AppKit
import SwiftUI

struct DualArchitectureBridgeView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var bridgeManager = DualArchitectureBridgeManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: DualArchTab = .dualInstalled
    @State private var searchQuery = ""
    @State private var copiedBootstrapCommand = false
    @State private var copiedRosettaCommand = false
    @State private var confirmingAction: ConfirmingAction?

    enum DualArchTab: String, CaseIterable, Identifiable {
        case dualInstalled = "Dual-Installed"
        case intelOnly = "Rosetta Intel Only"
        case arm64Only = "Apple Silicon Only"

        var id: String { rawValue }
    }

    struct ConfirmingAction: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let isDestructive: Bool
        let action: () async -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    systemTopologyCard

                    if let comparison = bridgeManager.comparison {
                        prefixComparisonCards(comparison)

                        if !comparison.translatedDaemons.filter(\.isTranslated).isEmpty {
                            translatedDaemonsCard(comparison.translatedDaemons.filter(\.isTranslated))
                        }

                        packageInventorySection(comparison)
                    } else if bridgeManager.isScanning {
                        loadingView
                    } else {
                        emptyStateView
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 780, minHeight: 620)
        .onAppear {
            Task {
                await bridgeManager.scanDualArchitectureEnvironment(activeManager: manager)
            }
        }
        .confirmationDialog(
            confirmingAction?.title ?? "Confirm Action",
            isPresented: Binding(
                get: { confirmingAction != nil },
                set: { if !$0 { confirmingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmingAction {
                Button(confirmingAction.isDestructive ? "Remove" : "Proceed", role: confirmingAction.isDestructive ? .destructive : nil) {
                    let act = confirmingAction.action
                    Task {
                        await act()
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            if let confirmingAction {
                Text(confirmingAction.message)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Dual-Architecture Bridge")
                    .font(.headline)
                Text("Inspect, compare, and bridge Apple Silicon (ARM64) and Intel (x86_64 Rosetta) Homebrew prefixes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if bridgeManager.isScanning {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task {
                    await bridgeManager.scanDualArchitectureEnvironment(activeManager: manager)
                }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(bridgeManager.isScanning || bridgeManager.isPerformingOperation)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - System Topology Card

    private var systemTopologyCard: some View {
        let comp = bridgeManager.comparison
        let hostArch = comp?.hostArchitecture ?? DualArchitectureBridgeManager.detectHostArchitecture()
        let rosetta = comp?.rosettaStatus

        return HStack(spacing: 16) {
            // Hardware Host
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "apple.logo")
                        .foregroundStyle(Color.purple)
                        .font(.system(size: 16, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Architecture")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(hostArch.rawValue)
                        .font(.subheadline.bold())
                }
            }

            Divider()
                .frame(height: 32)

            // Rosetta Status
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill((rosetta?.isInstalled == true ? Color.green : Color.orange).opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .foregroundStyle(rosetta?.isInstalled == true ? Color.green : Color.orange)
                        .font(.system(size: 15, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rosetta 2 Translation Engine")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(rosetta?.statusDescription ?? "Checking…")
                        .font(.subheadline.bold())
                        .foregroundStyle(rosetta?.isInstalled == true ? Color.primary : Color.orange)
                }
            }

            Spacer()

            if hostArch == .arm64, rosetta?.isInstalled == false {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DualArchitectureBridgeManager.rosettaInstallCommand, forType: .string)
                    copiedRosettaCommand = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedRosettaCommand = false
                    }
                } label: {
                    Label(copiedRosettaCommand ? "Command Copied!" : "Install Rosetta 2", systemImage: copiedRosettaCommand ? "checkmark" : "doc.on.doc")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Side-by-Side Prefix Comparison Cards

    private func prefixComparisonCards(_ comparison: DualArchitectureComparison) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // ARM64 Card
            prefixCard(
                title: "Apple Silicon (ARM64)",
                prefixPath: "/opt/homebrew",
                icon: "sparkles",
                iconColor: .purple,
                profile: comparison.arm64Profile,
                isActive: manager.brewPrefix == "/opt/homebrew"
            )

            // Intel x86_64 Card
            prefixCard(
                title: "Intel (x86_64 Rosetta)",
                prefixPath: "/usr/local",
                icon: "desktopcomputer",
                iconColor: .blue,
                profile: comparison.intelProfile,
                isActive: manager.brewPrefix == "/usr/local"
            )
        }
    }

    private func prefixCard(
        title: String,
        prefixPath: String,
        icon: String,
        iconColor: Color,
        profile: PrefixArchitectureProfile?,
        isActive: Bool
    ) -> some View {
        let isInstalled = profile?.prefix.isAvailable ?? false

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    Text(prefixPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                } else if isInstalled {
                    Text("READY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                } else {
                    Text("NOT INSTALLED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
            }

            Divider()

            if isInstalled, let profile {
                VStack(spacing: 8) {
                    HStack {
                        Label("\(profile.formulaCount) Formulae", systemImage: "shippingbox")
                            .font(.caption)
                        Spacer()
                        Label("\(profile.caskCount) Casks", systemImage: "macwindow")
                            .font(.caption)
                        Spacer()
                        Label(profile.formattedDiskUsage, systemImage: "internaldrive")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    if let ver = profile.homebrewVersion {
                        Text(ver)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !isActive {
                        Button {
                            bridgeManager.switchActivePrefix(to: prefixPath, manager: manager)
                        } label: {
                            Label("Switch to this Prefix", systemImage: "arrow.triangle.swap")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(bridgeManager.isPerformingOperation)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Homebrew installation detected at \(prefixPath).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if prefixPath == "/usr/local" {
                        Text("You can run Intel x86_64 Homebrew alongside Apple Silicon Homebrew to support legacy tools and compilers under Rosetta 2.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(DualArchitectureBridgeManager.intelBrewBootstrapCommand, forType: .string)
                            copiedBootstrapCommand = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedBootstrapCommand = false
                            }
                        } label: {
                            Label(copiedBootstrapCommand ? "Setup Command Copied!" : "Copy Intel Brew Bootstrap Command", systemImage: copiedBootstrapCommand ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isActive ? Color.green.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: isActive ? 1.5 : 1)
        )
    }

    // MARK: - Translated Daemons Card

    private func translatedDaemonsCard(_ daemons: [TranslatedDaemonItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Services Running Under Rosetta Translation (\(daemons.count))")
                    .font(.subheadline.bold())
            }

            Text("The following background daemons are compiled for Intel x86_64 and running via Rosetta 2 translation. Running them natively under Apple Silicon is recommended to minimize memory and battery usage.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(daemons) { daemon in
                HStack {
                    Text(daemon.serviceName)
                        .font(.caption.bold())
                    Spacer()
                    Text("x86_64 (Rosetta)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Package Cross-Architecture Inventory

    private func packageInventorySection(_ comparison: DualArchitectureComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Picker("Package Filter", selection: $selectedTab) {
                    Text("Dual-Installed (\(comparison.dualInstalledPackages.count))").tag(DualArchTab.dualInstalled)
                    Text("Rosetta Intel Only (\(comparison.intelOnlyPackages.count))").tag(DualArchTab.intelOnly)
                    Text("Apple Silicon Only (\(comparison.arm64OnlyPackages.count))").tag(DualArchTab.arm64Only)
                }
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter packages…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 140)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))
            }

            if let op = bridgeManager.operationStatus {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(op)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            // Tab Content
            switch selectedTab {
            case .dualInstalled:
                dualInstalledList(comparison.dualInstalledPackages)
            case .intelOnly:
                singleArchList(comparison.intelOnlyPackages, isIntel: true)
            case .arm64Only:
                singleArchList(comparison.arm64OnlyPackages, isIntel: false)
            }
        }
    }

    // MARK: - Lists

    private func dualInstalledList(_ packages: [DualPackageComparison]) -> some View {
        let filtered = packages.filter {
            searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(searchQuery)
        }

        return VStack(spacing: 0) {
            if filtered.isEmpty {
                Text(packages.isEmpty ? "No dual-installed packages found. Clean environment!" : "No matches for '\(searchQuery)'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ForEach(filtered) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.kind == .cask ? "macwindow" : "shippingbox.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline.bold())
                            HStack(spacing: 12) {
                                Text("ARM64: \(item.arm64Version)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text("Intel: \(item.intelVersion)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button("Remove from Intel") {
                            confirmingAction = ConfirmingAction(
                                title: "Remove '\(item.name)' from Intel Prefix?",
                                message: "This will remove the x86_64 build from /usr/local, freeing disk space while preserving your native Apple Silicon build in /opt/homebrew.",
                                isDestructive: true
                            ) {
                                try? await bridgeManager.uninstallFromPrefix(
                                    packageID: item.packageID,
                                    kind: item.kind,
                                    prefixPath: "/usr/local",
                                    manager: manager
                                )
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .disabled(bridgeManager.isPerformingOperation)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func singleArchList(_ packages: [CrossArchPackageItem], isIntel: Bool) -> some View {
        let filtered = packages.filter {
            searchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(searchQuery)
        }

        return VStack(spacing: 0) {
            if filtered.isEmpty {
                Text(packages.isEmpty ? "No packages in this category." : "No matches for '\(searchQuery)'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ForEach(filtered) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.kind == .cask ? "macwindow" : "shippingbox.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline.bold())
                            Text("Version: \(item.installedVersion) · \(item.prefixPath)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isIntel {
                            Button("Install Native ARM64") {
                                confirmingAction = ConfirmingAction(
                                    title: "Install Native ARM64 Build for '\(item.name)'?",
                                    message: "BrewStore will install the native Apple Silicon build of '\(item.name)' into /opt/homebrew.",
                                    isDestructive: false
                                ) {
                                    try? await bridgeManager.crossInstallPackage(
                                        packageID: item.packageID,
                                        kind: item.kind,
                                        targetPrefix: "/opt/homebrew",
                                        manager: manager
                                    )
                                }
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .disabled(bridgeManager.isPerformingOperation)
                        } else {
                            if bridgeManager.comparison?.intelProfile?.prefix.isAvailable == true {
                                Button("Cross-Install to Intel") {
                                    confirmingAction = ConfirmingAction(
                                        title: "Cross-Install '\(item.name)' to Intel Rosetta?",
                                        message: "BrewStore will install the x86_64 build of '\(item.name)' into /usr/local under Rosetta 2.",
                                        isDestructive: false
                                    ) {
                                        try? await bridgeManager.crossInstallPackage(
                                            packageID: item.packageID,
                                            kind: item.kind,
                                            targetPrefix: "/usr/local",
                                            manager: manager
                                        )
                                    }
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                .disabled(bridgeManager.isPerformingOperation)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Loading & Empty Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning dual-architecture environment, prefixes & packages…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No architecture profile generated yet.")
                .font(.subheadline)
            Button("Scan Environment") {
                Task {
                    await bridgeManager.scanDualArchitectureEnvironment(activeManager: manager)
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }
}
