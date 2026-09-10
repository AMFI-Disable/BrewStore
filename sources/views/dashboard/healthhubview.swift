import AppKit
import SwiftUI

enum HealthSubMode: String, CaseIterable, Identifiable {
    case snapshots = "Snapshots"
    case doctor = "Doctor Diagnostics"
    case storage = "Storage Cleanup"

    var id: String {
        rawValue
    }

    var section: BrewStoreSection {
        switch self {
        case .snapshots: .backups
        case .doctor: .backups
        case .storage: .backups
        }
    }
}

struct HealthHubView: View {
    @ObservedObject var manager: HomebrewManager
    @Binding var selection: BrewStoreSection?

    @State private var subMode: HealthSubMode = .snapshots
    @StateObject private var snapshotManager = BrewStoreSnapshotManager()
    @StateObject private var storageManager = BrewStoreDiskStorageAnalyzerManager.shared
    @StateObject private var doctorManager = BrewStoreDependencyDoctorManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // ZONE 1: Hub Header & Anchor Controls
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            Text("Health & Maintenance")
                                .font(.title2.bold())
                        }
                        Text("System snapshots, Homebrew Doctor diagnostics, and cache cleanup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Zone 1 Primary Contextual Action
                    HStack(spacing: 8) {
                        switch subMode {
                        case .snapshots:
                            Button {
                                snapshotManager.createSnapshot(manager: manager)
                            } label: {
                                Label("Create Snapshot", systemImage: "camera.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(manager.isOperating)
                        case .doctor:
                            Button {
                                doctorManager.autoHealToolchain(manager: manager)
                            } label: {
                                Label("Repair Common Issues", systemImage: "wrench.and.screwdriver.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(manager.isOperating)
                        case .storage:
                            Button(role: .destructive) {
                                storageManager.purgeCache(manager: manager)
                            } label: {
                                Label("Clean Caches", systemImage: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(manager.isOperating)
                        }

                        Button(action: manager.refresh) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(manager.isLoading || manager.isOperating)
                    }
                }

                // Zone 1: Segmented Switcher
                HStack {
                    Picker("Health Navigation", selection: $subMode) {
                        Text("Snapshots (\(snapshotManager.snapshots.count))").tag(HealthSubMode.snapshots)
                        Text("Doctor Diagnostics").tag(HealthSubMode.doctor)
                        Text("Disk Storage & Cleanup").tag(HealthSubMode.storage)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            // ZONE 3: Primary Content Canvas
            Group {
                switch subMode {
                case .snapshots:
                    SnapshotsView(manager: manager)
                case .doctor:
                    HealthScoreView(manager: manager)
                case .storage:
                    DiskStorageView(manager: manager)
                }
            }
            .id(subMode)
            .animation(nil, value: subMode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
