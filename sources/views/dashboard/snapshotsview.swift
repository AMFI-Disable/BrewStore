import AppKit
import SwiftUI

struct SnapshotsView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var snapshotManager = BrewStoreSnapshotManager()
    @ObservedObject private var preferences = BrewStorePreferences.shared
    @State private var selectedSnapshot: BrewStoreSnapshot?
    @State private var selectedTab = 0 // 0: Local Snapshots, 1: Multi-Machine Sync
    @State private var snapshotSearch = ""

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
                    Text("Mac Blueprint & Transfer").tag(1)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                if selectedTab == 0 {
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
                        onRestore()
                    } label: {
                        Label("Restore Missing Packages…", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderedProminent)
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
