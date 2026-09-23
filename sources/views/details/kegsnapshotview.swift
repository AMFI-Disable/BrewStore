import SwiftUI

struct KegSnapshotCardView: View {
    @ObservedObject var manager: HomebrewManager
    let packageID: String
    @StateObject private var snapshotManager = KegSnapshotManager.shared
    @State private var showingConfirmRollback = false
    @State private var targetVersionToRollback: String?
    @State private var showingSnapshotSuccess = false

    private var kegState: KegPackageState {
        snapshotManager.stateByPackage[packageID] ??
        snapshotManager.scanPackageKegs(for: packageID, prefix: manager.brewPrefix)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            headerRow

            if snapshotManager.isOperating {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(snapshotManager.statusMessage ?? "Processing keg operation…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let error = snapshotManager.lastError {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Installed Cellar Versions
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Installed Cellar Versions")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if kegState.installedVersions.isEmpty {
                    Text("No Cellar version records found for \(packageID).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(kegState.installedVersions) { ver in
                        installedVersionRow(ver)
                    }
                }
            }

            // Snapshots & Backups
            if !kegState.snapshots.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text("Archived Snapshots (\(kegState.snapshots.count))")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    ForEach(kegState.snapshots) { snap in
                        snapshotRow(snap)
                    }
                }
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
        .onAppear {
            _ = snapshotManager.scanPackageKegs(for: packageID, prefix: manager.brewPrefix)
        }
        .confirmationDialog(
            "Roll back to v\(targetVersionToRollback ?? "")?",
            isPresented: $showingConfirmRollback,
            titleVisibility: .visible
        ) {
            Button("Switch & Rollback", role: .destructive) {
                if let target = targetVersionToRollback {
                    performRollback(to: target)
                }
            }
            Button("Cancel", role: .cancel) {
                targetVersionToRollback = nil
            }
        } message: {
            Text("BrewStore will unlink the currently active version and repoint all binaries and symlinks to v\(targetVersionToRollback ?? "").")
        }
    }

    private var headerRow: some View {
        HStack {
            Label("Keg Versions & Instant Rollback", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            Spacer()

            if let activeVer = kegState.activeLinkedVersion {
                Button {
                    Task {
                        do {
                            _ = try await snapshotManager.createSnapshot(
                                packageID: packageID,
                                version: activeVer,
                                prefix: manager.brewPrefix
                            )
                            showingSnapshotSuccess = true
                        } catch {}
                    }
                } label: {
                    Label("Save Snapshot", systemImage: "camera")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(snapshotManager.isOperating)
            }
        }
    }

    @ViewBuilder
    private func installedVersionRow(_ ver: KegInstalledVersion) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: ver.isCurrentlyLinked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ver.isCurrentlyLinked ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text("v\(ver.version)")
                        .font(.body.monospacedDigit().bold())

                    if ver.isCurrentlyLinked {
                        Text("Active")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: Spacing.sm) {
                    Text(ver.displaySize)
                    if let date = ver.installedDate {
                        Text("•")
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !ver.isCurrentlyLinked {
                Button("Rollback") {
                    targetVersionToRollback = ver.version
                    showingConfirmRollback = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(snapshotManager.isOperating)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func snapshotRow(_ snap: KegSnapshotArchive) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "archivebox.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Snapshot v\(snap.version)")
                    .font(.body.monospacedDigit())

                HStack(spacing: Spacing.sm) {
                    Text(snap.displaySize)
                    Text("•")
                    Text(snap.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if snap.version != kegState.activeLinkedVersion {
                Button("Restore & Rollback") {
                    targetVersionToRollback = snap.version
                    showingConfirmRollback = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(snapshotManager.isOperating)
            }

            Button {
                try? snapshotManager.deleteSnapshot(archive: snap, prefix: manager.brewPrefix)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(snapshotManager.isOperating)
        }
        .padding(.vertical, 3)
    }

    private func performRollback(to target: String) {
        Task {
            do {
                try await snapshotManager.rollback(
                    packageID: packageID,
                    to: target,
                    prefix: manager.brewPrefix,
                    homebrewManager: manager
                )
            } catch {}
        }
    }
}
