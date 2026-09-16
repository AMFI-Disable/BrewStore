import AppKit
import SwiftUI

struct BrewStoreStatusHUDView: View {
    @ObservedObject var manager: HomebrewManager
    let onOpenHealth: () -> Void
    let onOpenServices: () -> Void

    @State private var isShowingServicesPopover = false
    @State private var isShowingClearLocksConfirmation = false
    @State private var serviceToToggle: (service: BrewStoreService, isStop: Bool)?
    @ObservedObject private var preferences = BrewStorePreferences.shared

    private var runningServicesCount: Int {
        manager.services.filter(\.isRunning).count
    }

    private var outdatedPackagesCount: Int {
        manager.packages.filter(\.isOutdated).count
    }

    private var healthScore: Int {
        var score = 100
        if outdatedPackagesCount > 0 {
            score -= min(30, outdatedPackagesCount * 3)
        }
        if manager.errorMessage != nil {
            score -= 15
        }
        return max(20, score)
    }

    private var healthColor: Color {
        if healthScore >= 90 {
            return .green
        }
        if healthScore >= 70 {
            return .orange
        }
        return .red
    }

    var body: some View {
        HStack(spacing: 6) {
            if manager.isOperating {
                // In-Flight Operation Active Pill
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)

                    let title = manager.activeOperationTitle ?? "Operating…"
                    let liveTime = BrewStoreUpdateEstimator.liveRemainingTimeString(manager: manager)
                    let displayTitle = liveTime.map { "\(title) (\($0))" } ?? title

                    Text(displayTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 190, alignment: .leading)

                    Button(action: manager.cancelCurrentOperation) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel Operation")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
            } else {
                // 1. Health Score Pill
                Button(action: onOpenHealth) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(healthColor)
                            .frame(width: 7, height: 7)

                        Text("\(healthScore)%")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)

                        Text("Health")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("System Health Score: \(healthScore)% (Click to inspect & optimize)")

                // 2. Services Mini-Pill & Quick Popover
                Button {
                    isShowingServicesPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 10))
                            .foregroundStyle(runningServicesCount > 0 ? Color.green : Color.secondary)

                        Text("\(runningServicesCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("\(runningServicesCount) Running Daemons (Click for quick controls)")
                .popover(isPresented: $isShowingServicesPopover, arrowEdge: .bottom) {
                    servicesQuickPopover
                }

                // 3. Auto-Refresh Status Pill
                Button(action: { manager.retryRefresh() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(manager.isLoading ? 360 : 0))
                            .animation(manager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: manager.isLoading)

                        if let date = manager.lastRefreshedAt {
                            Text(date, style: .relative)
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Sync")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoading)
                .help(manager.isLoading ? "Refreshing Homebrew data…" : "Click to refresh catalog now")

                // 4. Stale/Active Lock Indicator Pill
                if manager.isHomebrewLocked || manager.activeLockState.isLocked {
                    Button {
                        isShowingClearLocksConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text("Locked")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Homebrew is locked by a process or stale lockfile. Click to remove locks.")
                }
            }
        }
        .frame(height: 26)
        .animation(.easeInOut(duration: 0.2), value: manager.isOperating)
        .confirmationDialog(
            "Clear Homebrew Locks?",
            isPresented: $isShowingClearLocksConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Locks", role: .destructive) {
                manager.clearLocks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Active or stale lock files prevent installations, upgrades, and daemon controls. Clearing locks removes files in var/homebrew/locks so operations can proceed. Make sure no Terminal brew commands are running.")
        }
        .confirmationDialog(
            serviceToToggle?.isStop == true ? "Stop \(serviceToToggle?.service.name ?? "Service")?" : "Start \(serviceToToggle?.service.name ?? "Service")?",
            isPresented: Binding(get: { serviceToToggle != nil }, set: {
                if !$0 {
                    serviceToToggle = nil
                }
            }),
            titleVisibility: .visible
        ) {
            if let target = serviceToToggle {
                Button(target.isStop ? "Stop Service" : "Start Service", role: target.isStop ? .destructive : nil) {
                    manager.perform(service: target.service, action: target.isStop ? .stop : .start)
                }
                Button("Cancel", role: .cancel) {
                    serviceToToggle = nil
                }
            }
        } message: {
            if let target = serviceToToggle {
                Text(target.isStop ? "Background tasks for \(target.service.name) will cease until started again." : "Launch \(target.service.name) as a managed daemon.")
            }
        }
    }

    // MARK: - Quick Services Popover View

    private var servicesQuickPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Background Services", systemImage: "server.rack")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(runningServicesCount) Active")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(runningServicesCount > 0 ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(runningServicesCount > 0 ? .green : .secondary)
            }

            Divider()

            if manager.services.isEmpty {
                Text("No Homebrew background services detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(manager.services.prefix(6)) { service in
                            HStack {
                                Circle()
                                    .fill(service.isRunning ? Color.green : Color.secondary.opacity(0.4))
                                    .frame(width: 6, height: 6)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(service.name)
                                        .font(.caption.bold())
                                    Text(service.status.capitalized)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if service.isRunning {
                                    Button("Stop") {
                                        serviceToToggle = (service: service, isStop: true)
                                    }
                                    .controlSize(.mini)
                                } else {
                                    Button("Start") {
                                        serviceToToggle = (service: service, isStop: false)
                                    }
                                    .controlSize(.mini)
                                }
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            Divider()

            HStack {
                Button("View All in Services Tab") {
                    isShowingServicesPopover = false
                    onOpenServices()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Spacer()
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

// MARK: - Dedicated Reusable Lock Banner with Auto-Fix

struct BrewStoreLockBanner: View {
    @ObservedObject var manager: HomebrewManager
    @State private var showingConfirmation = false

    var isVisible: Bool {
        manager.isHomebrewLocked ||
            manager.activeLockState.isLocked ||
            manager.activeLockMessage != nil ||
            (manager.errorMessage?.localizedCaseInsensitiveContains("lock") == true)
    }

    var lockDetail: String {
        if let file = manager.activeLockState.lockFileName {
            if let pid = manager.activeLockState.holdingPID {
                return "Locked by \(file) (PID \(pid))."
            }
            return "Locked by \(file)."
        }
        return "Homebrew is currently locked by another process or a stale lockfile."
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Homebrew Operation Blocked by Lock")
                        .font(.subheadline.bold())
                    Text("\(lockDetail) If a previous brew command crashed or was terminated, clearing locks will restore operations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Button {
                    showingConfirmation = true
                } label: {
                    Label("Clear Locks…", systemImage: "lock.open.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .disabled(manager.isOperating && manager.activeLockMessage == nil)
            }
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.vertical, 4)
            .confirmationDialog(
                "Clear Homebrew Locks?",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Locks", role: .destructive) {
                    manager.clearLocks()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Active or stale lock files prevent installations, updates, and service controls. Clearing locks terminates lingering background brew workers and deletes lock files in var/homebrew/locks. Ensure no Terminal operations are running before proceeding.")
            }
        }
    }
}
