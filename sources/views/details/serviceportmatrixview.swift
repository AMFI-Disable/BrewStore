import AppKit
import SwiftUI

struct ServicePortMatrixView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var matrixManager = ServicePortMatrixManager.shared
    @State private var filterText = ""
    @State private var selectedPIDToKill: Int?
    @State private var showingKillConfirmation = false

    private var filteredEntries: [ListeningPortEntry] {
        if filterText.isEmpty {
            return matrixManager.entries
        }
        return matrixManager.entries.filter {
            "\($0.port)".contains(filterText) ||
            $0.processName.localizedCaseInsensitiveContains(filterText) ||
            ($0.associatedHomebrewService?.localizedCaseInsensitiveContains(filterText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if matrixManager.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning active listening ports with lsof…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matrixManager.entries.isEmpty {
                ContentUnavailableView(
                    "No Listening Ports Found",
                    systemImage: "network",
                    description: Text("Could not detect active TCP listening sockets or no daemons are currently bound.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if matrixManager.conflictCount > 0 {
                        conflictWarningBanner
                    }

                    searchAndFilterBar

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredEntries) { entry in
                                portRow(entry: entry)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .task {
            await matrixManager.scanPorts(services: manager.services)
        }
        .confirmationDialog(
            "Terminate Process?",
            isPresented: $showingKillConfirmation,
            titleVisibility: .visible
        ) {
            if let pid = selectedPIDToKill {
                Button("Terminate PID \(pid)", role: .destructive) {
                    matrixManager.terminateProcess(pid: pid)
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        await matrixManager.scanPorts(services: manager.services)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Terminating this process will free up the listening port so your Homebrew service can bind to it.")
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(.blue)
                .padding(8)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Service Port & Network Matrix").font(.title3.bold())
                Text("Inspect bound TCP sockets and diagnose background daemon port collisions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !matrixManager.isScanning {
                Button {
                    Task {
                        await matrixManager.scanPorts(services: manager.services)
                    }
                } label: {
                    Label("Rescan Ports", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
        .background(Color.secondary.opacity(0.04))
    }

    private var conflictWarningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(matrixManager.conflictCount) Port Conflict(s) Detected")
                    .font(.subheadline.bold())
                Text("One or more background processes are blocking Homebrew services from starting on their default ports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }

    private var searchAndFilterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Filter by port number (e.g. 5432, 6379) or process name…", text: $filterText)
                .textFieldStyle(.plain)
                .font(.caption)

            if !filterText.isEmpty {
                Button(action: { filterText = "" }) {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(filteredEntries.count) sockets")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.03))
    }

    private func portRow(entry: ListeningPortEntry) -> some View {
        HStack(spacing: 12) {
            // Port Badge
            Text(":\(entry.port)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.hasConflict ? Color.orange : Color.blue)
                .frame(width: 68, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.processName)
                        .font(.subheadline.bold())

                    Text("PID: \(entry.pid)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)

                    if let brewService = entry.associatedHomebrewService {
                        Text(brewService)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }

                if let conflict = entry.conflictDescription {
                    Text(conflict)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    HStack(spacing: 8) {
                        Text("Bound: \(entry.displayAddress)")
                        Text("•")
                        Text("User: \(entry.user)")
                        Text("•")
                        Text(entry.protocolType)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if entry.hasConflict {
                Button("Kill PID") {
                    selectedPIDToKill = entry.pid
                    showingKillConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(entry.hasConflict ? Color.orange.opacity(0.5) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
