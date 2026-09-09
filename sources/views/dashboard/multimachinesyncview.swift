import AppKit
import SwiftUI

struct MultiMachineSyncView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var syncManager = BrewStoreMultiMachineSyncManager.shared
    @StateObject private var transferManager = BrewStoreMacTransferManager.shared

    @State private var machineNameInput = ""
    @State private var selectedRemoteProfile: MacMachineProfile?
    @State private var showingBootstrapSheet = false
    @State private var bootstrapScript = ""
    @State private var copiedBootstrap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header & Action Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Blueprint & Setup Transfer").font(.headline)
                    Text("Export a complete Mac Blueprint capturing all Homebrew packages, taps, and Mac App Store apps. Bootstrap any Mac with 1 click.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    let current = syncManager.createCurrentMachineProfile(manager: manager, name: Host.current().localizedName ?? "My Mac")
                    syncManager.saveProfile(current)
                    selectedRemoteProfile = current
                } label: {
                    Label("Save Profile", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    let bundle = transferManager.createRigBundle(manager: manager, name: Host.current().localizedName ?? "My Mac")
                    bootstrapScript = transferManager.generateBootstrapScript(bundle: bundle)
                    showingBootstrapSheet = true
                } label: {
                    Label("Setup Script", systemImage: "terminal.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [.init(filenameExtension: "brewstore") ?? .json, .json]
                    if panel.runModal() == .OK, let url = panel.url {
                        if let bundle = transferManager.importBundleFromFile(url: url) {
                            let profile = MacMachineProfile(
                                id: UUID().uuidString,
                                name: bundle.rigName,
                                arch: bundle.architecture,
                                timestamp: bundle.exportDate,
                                formulae: bundle.formulae.map(\.name),
                                casks: bundle.casks.map(\.name),
                                taps: bundle.taps
                            )
                            syncManager.saveProfile(profile)
                            selectedRemoteProfile = profile
                            let current = syncManager.createCurrentMachineProfile(manager: manager, name: "Current Mac")
                            _ = syncManager.computeDiff(local: current, remote: profile)
                        }
                    }
                } label: {
                    Label("Import Blueprint…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    let currentBundle = transferManager.createRigBundle(manager: manager, name: Host.current().localizedName ?? "My Mac")
                    if let fileURL = transferManager.exportBundleToFile(bundle: currentBundle) {
                        let picker = NSSharingServicePicker(items: [fileURL])
                        if let window = NSApp.keyWindow, let contentView = window.contentView {
                            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                        }
                    }
                } label: {
                    Label("Export Blueprint", systemImage: "arrow.up.doc.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Blueprint Bootstrap Banner if Blueprint is imported or selected
            if let bundle = transferManager.importedBundle {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mac Blueprint: \(bundle.rigName)")
                                .font(.headline)
                            Text("\(bundle.totalPackagesCount) items (\(bundle.casks.count) casks, \(bundle.formulae.count) formulae, \(bundle.masApps.count) MAS apps, \(bundle.taps.count) taps)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            transferManager.bootstrapMac(bundle: bundle, manager: manager)
                        } label: {
                            if transferManager.isBootstrapping {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Bootstrapping…")
                                }
                            } else {
                                Label("Bootstrap This Mac", systemImage: "bolt.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(transferManager.isBootstrapping || manager.isOperating)
                    }

                    if let status = transferManager.bootstrapStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            // Saved Machine Profiles
            VStack(alignment: .leading, spacing: 10) {
                Text("Saved Mac Profiles").font(.subheadline.bold())

                if syncManager.savedProfiles.isEmpty {
                    HStack {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("No machine profiles saved yet. Click 'Save Current Mac Profile' or import a setup profile above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(syncManager.savedProfiles) { profile in
                                Button {
                                    selectedRemoteProfile = profile
                                    let current = syncManager.createCurrentMachineProfile(manager: manager, name: "Current Mac")
                                    _ = syncManager.computeDiff(local: current, remote: profile)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: "laptopcomputer").font(.headline)
                                            Spacer()
                                            Text(profile.arch.contains("Apple") || profile.arch.contains("arm64") ? "arm64" : "x86")
                                                .font(.caption2.monospaced())
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.secondary.opacity(0.1), in: Capsule())
                                        }

                                        Text(profile.name).font(.subheadline.bold())
                                        Text("\(profile.totalPackagesCount) packages • \(profile.taps.count) taps")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .frame(width: 200, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedRemoteProfile?.id == profile.id ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: selectedRemoteProfile?.id == profile.id ? 2 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Cross-Mac Environment Diff Inspector
            if let diff = syncManager.activeDiff, let remote = selectedRemoteProfile {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Comparing: Current Mac vs \(remote.name)", systemImage: "arrow.left.arrow.right")
                            .font(.headline)
                        Spacer()
                        Text("\(diff.commonCount) shared packages").font(.caption.monospaced()).foregroundStyle(.green)
                    }

                    // Missing on Current Mac
                    if diff.totalMissingOnLocal > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                                Text("Missing on This Mac (\(diff.totalMissingOnLocal) packages)").font(.subheadline.bold())
                                Spacer()

                                Button("Install All Missing") {
                                    for id in diff.missingOnLocalFormulae {
                                        let pkg = manager.packages.first(where: { $0.id == id }) ?? BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: .formula)
                                        manager.perform(package: pkg, action: .install)
                                    }
                                    for id in diff.missingOnLocalCasks {
                                        let pkg = manager.packages.first(where: { $0.id == id }) ?? BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: .cask)
                                        manager.perform(package: pkg, action: .install)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(manager.isOperating)
                            }

                            // Pills of missing tools
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(diff.missingOnLocalFormulae, id: \.self) { pkg in
                                        HStack(spacing: 4) {
                                            Image(systemName: "terminal.fill").font(.system(size: 9))
                                            Text(pkg).font(.caption2.monospaced().bold())
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.orange)
                                    }
                                    ForEach(diff.missingOnLocalCasks, id: \.self) { pkg in
                                        HStack(spacing: 4) {
                                            Image(systemName: "app.fill").font(.system(size: 9))
                                            Text(pkg).font(.caption2.monospaced().bold())
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("All packages from \(remote.name) are installed on this Mac! Your environment is in complete sync.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .sheet(isPresented: $showingBootstrapSheet) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Quick Setup Script", systemImage: "terminal.fill").font(.headline)
                    Spacer()
                    Button("Done") { showingBootstrapSheet = false }
                        .controlSize(.small)
                }

                Text("Run this script in Terminal on another Mac to install Homebrew, taps, and all your packages automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(bootstrapScript)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                .frame(height: 280)

                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bootstrapScript, forType: .string)
                        copiedBootstrap = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedBootstrap = false }
                    } label: {
                        Label(copiedBootstrap ? "Copied to Clipboard!" : "Copy Script", systemImage: copiedBootstrap ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(20)
            .frame(width: 580, height: 440)
        }
    }
}
