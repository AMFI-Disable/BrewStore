import AppKit
import SwiftUI

struct SnapshotsView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var snapshotManager = BrewStoreSnapshotManager()
    @ObservedObject private var preferences = BrewStorePreferences.shared
    @State private var selectedSnapshot: BrewStoreSnapshot?
    @State private var selectedTab = 0 // 0: Local Snapshots, 1: Multi-Machine Sync, 2: Time Machine Timeline
    @State private var snapshotSearch = ""
    @State private var snapshotForReplay: BrewStoreSnapshot?

    private var baseSnapshots: [BrewStoreSnapshot] {
        let q = snapshotSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return snapshotManager.snapshots }
        return snapshotManager.snapshots.filter {
            $0.formattedDate.lowercased().contains(q) ||
                $0.fileURL.lastPathComponent.lowercased().contains(q) ||
                $0.casks.contains { $0.lowercased().contains(q) } ||
                $0.formulae.contains { $0.lowercased().contains(q) }
        }
    }

    private var inSyncSnapshotsCount: Int {
        baseSnapshots.filter { snapshot in
            let diff = snapshotManager.computeDiff(for: snapshot, currentPackages: manager.packages, currentTaps: manager.taps)
            return !diff.hasDifferences
        }.count
    }

    private var filteredSnapshots: [BrewStoreSnapshot] {
        if preferences.hideIdenticalSnapshots {
            return baseSnapshots.filter { snapshot in
                let diff = snapshotManager.computeDiff(for: snapshot, currentPackages: manager.packages, currentTaps: manager.taps)
                return diff.hasDifferences
            }
        }
        return baseSnapshots
    }

    var showHeader: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            if showHeader {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Snapshots & Sync").font(.largeTitle.bold())
                        Text("Save snapshots of your installed packages and sync setups between Macs.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    if selectedTab == 0 {
                        HStack(spacing: 8) {
                            Menu {
                                Button {
                                    snapshotManager.exportCurrentState(manager: manager)
                                } label: {
                                    Label("Export Current System Brewfile…", systemImage: "square.and.arrow.up")
                                }
                                if let selected = selectedSnapshot {
                                    Button {
                                        snapshotManager.exportSnapshot(selected)
                                    } label: {
                                        Label("Export Selected Snapshot…", systemImage: "doc.badge.arrow.up")
                                    }
                                }
                            } label: {
                                Label("Export Brewfile", systemImage: "square.and.arrow.up")
                            }
                            .menuStyle(.borderedButton)

                            Menu {
                                ForEach(SnapshotBackupFrequency.allCases) { freq in
                                    Button {
                                        snapshotManager.backupFrequency = freq
                                    } label: {
                                        HStack {
                                            Text(freq.rawValue)
                                            if snapshotManager.backupFrequency == freq {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label("Backup: \(snapshotManager.backupFrequency.rawValue)", systemImage: "clock.badge.checkmark")
                            }
                            .menuStyle(.borderedButton)

                            Button {
                                selectedTab = 1
                            } label: {
                                Label("Mac Blueprint", systemImage: "sparkles.rectangle.stack")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                snapshotManager.createSnapshot(manager: manager)
                            } label: {
                                Label("Create Snapshot", systemImage: "camera.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manager.isOperating)
                        }
                    }
                }
                .padding()
            }

            HStack(spacing: Spacing.md) {
                Picker("", selection: $selectedTab) {
                    Text("Package Snapshots (\(snapshotManager.snapshots.count))").tag(0)
                    Text("Cellar Time Machine").tag(2)
                    Text("Mac Blueprint & Transfer").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                if selectedTab == 0 || selectedTab == 2 {
                    BrewStoreSectionSearchBar(text: $snapshotSearch, placeholder: "Search snapshots & backup packages…", count: filteredSnapshots.count)
                        .frame(minWidth: 180, maxWidth: 260)

                    if inSyncSnapshotsCount > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                preferences.hideIdenticalSnapshots.toggle()
                            }
                        } label: {
                            Label(
                                preferences.hideIdenticalSnapshots
                                    ? "Hidden In-Sync (\(inSyncSnapshotsCount))"
                                    : "Hide In-Sync (\(inSyncSnapshotsCount))",
                                systemImage: preferences.hideIdenticalSnapshots ? "eye.slash.fill" : "eye"
                            )
                            .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(preferences.hideIdenticalSnapshots ? .accentColor : .secondary)
                        .help(preferences.hideIdenticalSnapshots ? "Show in-sync/identical snapshots" : "Hide snapshots that match current system state")
                    }

                    if !showHeader {
                        Menu {
                            Button {
                                snapshotManager.exportCurrentState(manager: manager)
                            } label: {
                                Label("Export Current System Brewfile…", systemImage: "square.and.arrow.up")
                            }
                            if let selected = selectedSnapshot {
                                Button {
                                    snapshotManager.exportSnapshot(selected)
                                } label: {
                                    Label("Export Selected Snapshot…", systemImage: "doc.badge.arrow.up")
                                }
                            }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)

                        Button {
                            selectedTab = 1
                        } label: {
                            Label("Mac Blueprint", systemImage: "sparkles.rectangle.stack")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            snapshotManager.createSnapshot(manager: manager)
                        } label: {
                            Label("Create Snapshot", systemImage: "camera.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(manager.isOperating)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, showHeader ? 0 : Spacing.sm)
            .padding(.bottom, Spacing.sm)

            Divider()

            Group {
                if selectedTab == 1 {
                    ScrollView {
                        MultiMachineSyncView(manager: manager, showHeader: false)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.md)
                    }
                } else if selectedTab == 2 {
                    CellarTimeMachineTimelineView(
                        snapshots: filteredSnapshots,
                        manager: manager,
                        snapshotManager: snapshotManager,
                        onSelectSnapshot: { snap in
                            selectedSnapshot = snap
                            selectedTab = 0
                        }
                    )
                } else if snapshotManager.snapshots.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Snapshots Yet").font(.headline)
                        Text("Create a snapshot to record your currently installed packages and restore them at any time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Create First Snapshot") {
                            snapshotManager.createSnapshot(manager: manager)
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredSnapshots.isEmpty {
                    if preferences.hideIdenticalSnapshots, inSyncSnapshotsCount > 0 {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.green)
                            Text("All Snapshots In-Sync")
                                .font(.title3.bold())
                            Text("All \(inSyncSnapshotsCount) recorded snapshot\(inSyncSnapshotsCount == 1 ? " is" : "s are") identical to your current system state and hidden to avoid clutter.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    preferences.hideIdenticalSnapshots = false
                                }
                            } label: {
                                Label("Show In-Sync Snapshots", systemImage: "eye")
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "No Matching Snapshots",
                            systemImage: "magnifyingglass",
                            description: Text("No snapshots match \"\(snapshotSearch)\".")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    HSplitView {
                        // Left Snapshot List
                        List(filteredSnapshots, selection: $selectedSnapshot) { snapshot in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(snapshot.formattedDate)
                                        .font(.headline)
                                }
                                Text("\(snapshot.totalCount) packages (\(snapshot.casks.count) casks, \(snapshot.formulae.count) formulae)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(snapshot)
                            .padding(.vertical, 4)
                            .contextMenu {
                                Button("Export Brewfile…") {
                                    snapshotManager.exportSnapshot(snapshot)
                                }

                                Button("Restore (Install Missing Packages)") {
                                    triggerRestore(for: snapshot)
                                }
                                .disabled(manager.isOperating || !manager.isAvailable)

                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([snapshot.fileURL])
                                }

                                Button("Copy Snapshot Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(snapshot.fileURL.path, forType: .string)
                                }

                                Divider()

                                Button("Restore Missing Packages…") {
                                    triggerRestore(for: snapshot)
                                }
                                .disabled(manager.isOperating || !manager.isAvailable)
                            }
                        }
                        .frame(minWidth: 260, maxWidth: 360)

                        // Right Diff Inspector
                        if let snapshot = selectedSnapshot {
                            SnapshotDetailInspector(
                                snapshot: snapshot,
                                diff: snapshotManager.computeDiff(for: snapshot, currentPackages: manager.packages, currentTaps: manager.taps),
                                manager: manager,
                                onDelete: {
                                    snapshotManager.deleteSnapshot(snapshot)
                                    selectedSnapshot = nil
                                },
                                onExport: {
                                    snapshotManager.exportSnapshot(snapshot)
                                },
                                onRestore: {
                                    triggerRestore(for: snapshot)
                                },
                                onReplay: {
                                    snapshotForReplay = snapshot
                                }
                            )
                        } else {
                            VStack {
                                Spacer()
                                Text("Select a snapshot to inspect state diff").foregroundStyle(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .id(selectedTab)
            .animation(nil, value: selectedTab)
        }
        .sheet(item: $snapshotForReplay) { snap in
            TimeMachineReplaySheet(snapshot: snap, manager: manager)
        }
        .onAppear {
            if selectedSnapshot == nil || (selectedSnapshot != nil && !filteredSnapshots.contains(where: { $0.id == selectedSnapshot?.id })) {
                selectedSnapshot = filteredSnapshots.first
            }
            snapshotManager.checkScheduledBackup(manager: manager)
        }
        .onChange(of: preferences.hideIdenticalSnapshots) { _, _ in
            if let selected = selectedSnapshot, !filteredSnapshots.contains(where: { $0.id == selected.id }) {
                selectedSnapshot = filteredSnapshots.first
            }
        }
    }

    private func triggerRestore(for snapshot: BrewStoreSnapshot) {
        if let summary = BrewStoreBrewfileImporter.shared.parseBrewfile(from: snapshot.fileURL, manager: manager) {
            BrewStoreActionReviewCoordinator.shared.requestBrewfileImport(entries: summary.entries, taps: summary.taps) {
                manager.installBrewfile(from: snapshot.fileURL)
            }
        } else {
            manager.installBrewfile(from: snapshot.fileURL)
        }
    }
}

private struct SnapshotDetailInspector: View {
    let snapshot: BrewStoreSnapshot
    let diff: BrewStoreSnapshotDiff
    @ObservedObject var manager: HomebrewManager
    let onDelete: () -> Void
    let onExport: () -> Void
    let onRestore: () -> Void
    let onReplay: () -> Void

    @State private var packageQuery = ""
    @State private var showingDeleteConfirmation = false

    private var filteredMissingFormulae: [String] {
        filterList(diff.missingFormulae)
    }

    private var filteredMissingCasks: [String] {
        filterList(diff.missingCasks)
    }

    private var filteredAddedFormulae: [String] {
        filterList(diff.addedFormulae)
    }

    private var filteredAddedCasks: [String] {
        filterList(diff.addedCasks)
    }

    private var filteredCasks: [String] {
        filterList(snapshot.casks)
    }

    private var filteredFormulae: [String] {
        filterList(snapshot.formulae)
    }

    private var filteredMissingTaps: [String] {
        filterList(diff.missingTaps)
    }

    private var filteredTaps: [String] {
        filterList(snapshot.taps)
    }

    private func filterList(_ list: [String]) -> [String] {
        let q = packageQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.formattedDate).font(.title2.bold())
                        Text("Snapshot File: \(snapshot.fileURL.lastPathComponent)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        onExport()
                    } label: {
                        Label("Export Brewfile…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([snapshot.fileURL])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        onReplay()
                    } label: {
                        Label("Time Machine Replay…", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                    .disabled(manager.isOperating)

                    Button {
                        onRestore()
                    } label: {
                        Label("Restore Missing Packages…", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(manager.isOperating)

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Delete Snapshot")
                }
                .confirmationDialog("Delete Snapshot?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                    Button("Delete Snapshot (\(snapshot.fileURL.lastPathComponent))", role: .destructive) {
                        onDelete()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete the snapshot file from disk. Installed packages remain untouched.")
                }

                // In-Section Filter
                BrewStoreSectionSearchBar(text: $packageQuery, placeholder: "Search recorded package names in snapshot…")

                Divider()

                // Safety Guidance
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Restoring installs any missing packages recorded in this snapshot. Software installed after this snapshot remains untouched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                // Snapshot Metrics Overview
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recorded Packages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(snapshot.totalCount)")
                            .font(.title3.bold())
                        Text("\(snapshot.casks.count) apps · \(snapshot.formulae.count) CLI")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Package Sources")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(snapshot.taps.count)")
                            .font(.title3.bold())
                        Text("Repositories mapped")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Sync State")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(diff.hasDifferences ? "\(diff.totalChanges) Changes" : "Identical")
                            .font(.title3.bold())
                            .foregroundStyle(diff.hasDifferences ? Color.orange : Color.green)
                        Text(diff.hasDifferences ? "Differs from current" : "Fully in sync")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }

                // State Diff Summary
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: diff.hasDifferences ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                            .foregroundStyle(diff.hasDifferences ? Color.orange : Color.green)
                        Text("System State Comparison")
                            .font(.headline)
                        Spacer()
                        if diff.hasDifferences {
                            Text("\(diff.totalChanges) Differences")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    if !diff.hasDifferences {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("Current system perfectly matches this snapshot. No missing or extra packages.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(spacing: 8) {
                            if !filteredMissingTaps.isEmpty {
                                DiffGroupView(title: "Missing Taps (in snapshot, not currently tapped)", items: filteredMissingTaps, isAddition: false)
                            }

                            if !filteredMissingFormulae.isEmpty {
                                DiffGroupView(title: "Missing Formulae (in snapshot, not currently installed)", items: filteredMissingFormulae, isAddition: false)
                            }

                            if !filteredMissingCasks.isEmpty {
                                DiffGroupView(title: "Missing Applications (in snapshot, not currently installed)", items: filteredMissingCasks, isAddition: false)
                            }

                            if !filteredAddedFormulae.isEmpty {
                                DiffGroupView(title: "Added Formulae (installed after this snapshot was recorded)", items: filteredAddedFormulae, isAddition: true)
                            }

                            if !filteredAddedCasks.isEmpty {
                                DiffGroupView(title: "Added Applications (installed after this snapshot was recorded)", items: filteredAddedCasks, isAddition: true)
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                // Snapshot Recorded Package Inventory
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Recorded Packages in Snapshot (\(snapshot.totalCount))")
                            .font(.headline)
                        Spacer()
                    }

                    if !filteredTaps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Third-Party Taps (\(filteredTaps.count))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                                ForEach(filteredTaps, id: \.self) { tap in
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.3.layers.3d.down.forward").foregroundStyle(.purple).font(.caption)
                                        Text(tap).font(.caption.monospaced()).lineLimit(1)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }

                    if !filteredCasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Applications / Casks (\(filteredCasks.count))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                                ForEach(filteredCasks, id: \.self) { cask in
                                    HStack(spacing: 6) {
                                        Image(systemName: "app.fill").foregroundStyle(.blue).font(.caption)
                                        Text(cask).font(.caption.monospaced()).lineLimit(1)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }

                    if !filteredFormulae.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Command-Line Formulae (\(filteredFormulae.count))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                                ForEach(filteredFormulae, id: \.self) { formula in
                                    HStack(spacing: 6) {
                                        Image(systemName: "terminal.fill").foregroundStyle(.green).font(.caption)
                                        Text(formula).font(.caption.monospaced()).lineLimit(1)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DiffGroupView: View {
    let title: String
    let items: [String]
    let isAddition: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: isAddition ? "plus.circle.fill" : "minus.circle.fill")
                    .foregroundStyle(isAddition ? Color.blue : Color.orange)
                    .font(.caption)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(isAddition ? Color.blue : Color.orange)
                Spacer()
                Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isAddition ? Color.blue.opacity(0.05) : Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TimeMachineReplaySheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: BrewStoreSnapshot
    @ObservedObject var manager: HomebrewManager
    @StateObject private var rollbackManager = BrewStoreSnapshotRollbackManager.shared

    private var plan: SnapshotRollbackPlan {
        rollbackManager.computePlan(
            currentPackages: manager.packages,
            currentServices: manager.services,
            currentTaps: manager.taps,
            snapshot: snapshot
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundStyle(Color.purple)
                        Text("Cellar Time Machine Replay").font(.title2.bold())
                    }
                    Text("Revert your Homebrew system state to snapshot from \(snapshot.formattedDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Divider()

            if rollbackManager.isRollingBack {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text(rollbackManager.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if plan.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.green)
                    Text("Already at Target State").font(.headline)
                    Text("Your current system packages match this snapshot exactly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Blast Radius Alert Card
                        if plan.hasCriticalBlastRadius {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                                        .foregroundStyle(Color.red)
                                    Text("Blast Radius Safeguard Warning")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color.red)
                                }
                                Text("Reverting to this snapshot requires uninstalling packages with active reverse dependencies or background daemons:")
                                    .font(.caption)

                                if !plan.affectedRunningServices.isEmpty {
                                    HStack(spacing: 6) {
                                        Text("Active Daemons Disrupted:").font(.caption.bold())
                                        Text(plan.affectedRunningServices.joined(separator: ", "))
                                            .font(.caption.monospaced())
                                            .foregroundStyle(Color.red)
                                    }
                                }

                                if plan.totalBrokenDownstreamPackagesCount > 0 {
                                    HStack(spacing: 6) {
                                        Text("Reverse Dependents Broken:").font(.caption.bold())
                                        Text("\(plan.totalBrokenDownstreamPackagesCount) downstream package(s)")
                                            .font(.caption)
                                            .foregroundStyle(Color.orange)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.25), lineWidth: 1))
                        }

                        // Summary Statistics
                        HStack(spacing: 12) {
                            statBox(title: "UNINSTALL", count: plan.packagesToUninstall.count, color: Color.red, icon: "trash.fill")
                            statBox(title: "REINSTALL", count: plan.packagesToReinstall.count, color: Color.green, icon: "arrow.down.circle.fill")
                            statBox(title: "RESTORE TAPS", count: plan.missingTaps.count, color: Color.blue, icon: "spigot.fill")
                        }

                        if !plan.packagesToUninstall.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Packages to Uninstall (\(plan.packagesToUninstall.count))").font(.caption.bold()).foregroundStyle(Color.red)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                                    ForEach(plan.packagesToUninstall, id: \.self) { pkg in
                                        HStack(spacing: 4) {
                                            Image(systemName: "minus.circle.fill").font(.caption2).foregroundStyle(Color.red)
                                            Text(pkg).font(.caption.monospaced()).lineLimit(1)
                                        }
                                        .padding(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }

                        if !plan.packagesToReinstall.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Packages to Reinstall (\(plan.packagesToReinstall.count))").font(.caption.bold()).foregroundStyle(Color.green)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                                    ForEach(plan.packagesToReinstall, id: \.self) { pkg in
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill").font(.caption2).foregroundStyle(Color.green)
                                            Text(pkg).font(.caption.monospaced()).lineLimit(1)
                                        }
                                        .padding(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)

                Divider()

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button {
                        rollbackManager.executeRollback(plan: plan, manager: manager) { success in
                            if success {
                                dismiss()
                            }
                        }
                    } label: {
                        Label("Replay & Revert System", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.purple)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }
            }
        }
        .padding(20)
        .frame(width: 580, height: 460)
    }

    private func statBox(title: String, count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)").font(.headline)
                Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CellarTimeMachineTimelineView: View {
    let snapshots: [BrewStoreSnapshot]
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var snapshotManager: BrewStoreSnapshotManager
    let onSelectSnapshot: (BrewStoreSnapshot) -> Void

    @State private var replayTargetSnapshot: BrewStoreSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cellar Time Machine Timeline").font(.headline)
                        Text("Chronological record of system states. Select any checkpoint to inspect deltas or rollback.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        snapshotManager.createSnapshot(name: "Time Machine Checkpoint", manager: manager)
                    } label: {
                        Label("Capture Checkpoint Now", systemImage: "camera.badge.clock")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }

                if snapshots.isEmpty {
                    ContentUnavailableView("No Timeline Checkpoints", systemImage: "clock.arrow.2.circlepath", description: Text("Capture a snapshot to initialize the Cellar Time Machine timeline."))
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snap in
                            let diff = snapshotManager.computeDiff(for: snap, currentPackages: manager.packages, currentTaps: manager.taps)
                            HStack(alignment: .top, spacing: 14) {
                                // Timeline node and vertical connector
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(diff.hasDifferences ? Color.purple : Color.green)
                                        .frame(width: 14, height: 14)
                                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                                    if index < snapshots.count - 1 {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.2))
                                            .frame(width: 2)
                                            .frame(maxHeight: .infinity)
                                    }
                                }
                                .frame(width: 20)

                                // Card Content
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(snap.formattedDate).font(.subheadline.bold())
                                            Text(snap.name).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()

                                        if !diff.hasDifferences {
                                            Text("Live System Match")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.12), in: Capsule())
                                                .foregroundStyle(Color.green)
                                        } else {
                                            HStack(spacing: 4) {
                                                if !diff.missingFormulae.isEmpty || !diff.missingCasks.isEmpty {
                                                    Text("+\(diff.missingFormulae.count + diff.missingCasks.count) to restore")
                                                        .font(.caption2.bold())
                                                        .foregroundStyle(Color.blue)
                                                }
                                                if !diff.addedFormulae.isEmpty || !diff.addedCasks.isEmpty {
                                                    Text("-\(diff.addedFormulae.count + diff.addedCasks.count) to remove")
                                                        .font(.caption2.bold())
                                                        .foregroundStyle(Color.orange)
                                                }
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.1), in: Capsule())
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        Text("\(snap.totalCount) total packages (\(snap.casks.count) casks, \(snap.formulae.count) formulae)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        Button("View Details") {
                                            onSelectSnapshot(snap)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)

                                        Button {
                                            replayTargetSnapshot = snap
                                        } label: {
                                            Label("Replay & Revert…", systemImage: "clock.arrow.circlepath")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Color.purple)
                                        .controlSize(.mini)
                                        .disabled(manager.isOperating)
                                    }
                                }
                                .padding(12)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                                .padding(.bottom, 12)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .sheet(item: $replayTargetSnapshot) { snap in
            TimeMachineReplaySheet(snapshot: snap, manager: manager)
        }
    }
}

