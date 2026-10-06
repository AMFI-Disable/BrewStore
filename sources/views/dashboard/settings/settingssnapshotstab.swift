import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsSnapshotsTab: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var snapshotManager = BrewStoreSnapshotManager()
    @StateObject private var rollbackManager = BrewStoreSnapshotRollbackManager.shared

    @State private var selectedRollbackSnapshot: BrewStoreSnapshot?
    @State private var showingRollbackConfirmation = false
    @State private var pendingRollbackPlan: SnapshotRollbackPlan?
    @State private var showingBrewfileImporter = false
    @State private var showingBrewfileConfirmation = false
    @State private var selectedBrewfileURL: URL?
    @State private var brewfileContents = ""
    @State private var brewfileError: String?
    @State private var brewfileDiff: BrewStoreBrewfileDiff?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MultiMachineSyncView(manager: manager)
            dotfilesAutoSyncSection
            brewfileExportSection
            brewfileImportSection
            snapshotRollbackSection
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

    private var dotfilesAutoSyncSection: some View {
        SettingsCardSection(title: "Automated Dotfiles & Brewfile Auto-Sync", icon: "arrow.triangle.2.circlepath.circle") {
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
    }

    private var brewfileExportSection: some View {
        SettingsCardSection(title: "Brewfile Export", icon: "square.and.arrow.up") {
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
    }

    private var brewfileImportSection: some View {
        SettingsCardSection(title: "Brewfile Import & State Sync", icon: "square.and.arrow.down") {
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
                HumanizedErrorBanner(
                    rawError: brewfileError,
                    onDismiss: {
                        self.brewfileError = nil
                    }
                )
            }
        }
    }

    private var snapshotRollbackSection: some View {
        SettingsCardSection(title: "Time Machine Snapshot Rollback", icon: "clock.arrow.circlepath") {
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
