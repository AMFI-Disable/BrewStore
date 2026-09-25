import AppKit
import SwiftUI

enum TapBenchmarkFilter: String, CaseIterable, Identifiable {
    case all = "All Taps"
    case healthy = "Healthy"
    case outdated = "Behind Remote"
    case highLatency = "High Latency"
    case attention = "Attention Needed"

    var id: String { rawValue }
}

struct TapHealthBenchmarkView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var healthManager = BrewStoreTapHealthManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var filter: TapBenchmarkFilter = .all
    @State private var searchFilter: String = ""
    @State private var tapToUntap: TapHealthReport?
    @State private var tapToSwitchProtocol: TapHealthReport?
    @State private var statusToast: String?
    @State private var isSyncingAll = false

    private var effectivePrefix: String {
        manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
    }

    private var allReports: [TapHealthReport] {
        Array(healthManager.reports.values).sorted { $0.tapName < $1.tapName }
    }

    private var filteredReports: [TapHealthReport] {
        allReports.filter { report in
            let matchesSearch = searchFilter.isEmpty ||
                report.tapName.localizedCaseInsensitiveContains(searchFilter) ||
                (report.remoteURL?.localizedCaseInsensitiveContains(searchFilter) ?? false) ||
                (report.branch?.localizedCaseInsensitiveContains(searchFilter) ?? false)

            guard matchesSearch else { return false }

            switch filter {
            case .all:
                return true
            case .healthy:
                return report.status == .healthy
            case .outdated:
                return report.hasCommitLag || report.status == .commitLag
            case .highLatency:
                return report.isHighLatency || report.status == .highLatency
            case .attention:
                return report.status != .healthy
            }
        }
    }

    private var averageLatencyMs: Double? {
        let latencies = allReports.compactMap(\.latencyMilliseconds)
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    private var outdatedCount: Int {
        allReports.filter { $0.hasCommitLag || $0.status == .commitLag }.count
    }

    private var shallowCount: Int {
        allReports.filter(\.isShallow).count
    }

    private var highLatencyCount: Int {
        allReports.filter { $0.isHighLatency || $0.status == .highLatency }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

            Divider()

            filterBarView
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)

            Divider()

            ZStack {
                if healthManager.isAuditing && allReports.isEmpty {
                    loadingView
                } else if allReports.isEmpty {
                    emptyTapsView
                } else {
                    contentCanvas
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let toast = statusToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(toast)
                        .font(.caption.bold())
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.95), in: Capsule())
                .shadow(radius: 4)
                .padding(.bottom, Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 560, idealHeight: 640)
        .onAppear {
            if healthManager.reports.isEmpty {
                refreshAudit()
            }
        }
        .confirmationDialog(
            "Untap \(tapToUntap?.tapName ?? "")?",
            isPresented: Binding(
                get: { tapToUntap != nil },
                set: { if !$0 { tapToUntap = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Untap Repository", role: .destructive) {
                if let tap = tapToUntap {
                    performUntap(tapName: tap.tapName)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let tap = tapToUntap {
                let count = manager.packages.filter { $0.tap == tap.tapName }.count
                if count > 0 {
                    Text("Warning: You have \(count) installed package\(count == 1 ? "" : "s") originating from '\(tap.tapName)'. Untapping may prevent future updates.")
                } else {
                    Text("This will remove the tap repository '\(tap.tapName)' from your local Homebrew installation.")
                }
            }
        }
        .confirmationDialog(
            "Switch \(tapToSwitchProtocol?.tapName ?? "") Protocol?",
            isPresented: Binding(
                get: { tapToSwitchProtocol != nil },
                set: { if !$0 { tapToSwitchProtocol = nil } }
            ),
            titleVisibility: .visible
        ) {
            let targetProto: TapTransportProtocol = (tapToSwitchProtocol?.transportProtocol == .https ? .ssh : .https)
            Button("Switch to \(targetProto.rawValue)") {
                if let tap = tapToSwitchProtocol {
                    performSwitchProtocol(tapName: tap.tapName, to: targetProto)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let targetURL = tapToSwitchProtocol?.alternateProtocolURL {
                Text("This will update the git remote origin to:\n\(targetURL)")
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Tap Health & Upstream Latency Benchmark")
                        .font(.title2.bold())

                    if healthManager.isAuditing || healthManager.isBenchmarking || isSyncingAll {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("Audits Git repository health, upstream commit lag, and network latency for third-party and official taps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if outdatedCount > 0 {
                Button {
                    batchSyncOutdated()
                } label: {
                    Label("Sync Outdated (\(outdatedCount))", systemImage: "arrow.triangle.pull")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(healthManager.isOperating || isSyncingAll)
            }

            Button {
                Task {
                    await healthManager.benchmarkAllLatencies()
                    showToast("Latency benchmark complete.")
                }
            } label: {
                Label("Test Latencies", systemImage: "gauge.with.needle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(healthManager.isBenchmarking || healthManager.isOperating)

            Button {
                refreshAudit()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(healthManager.isAuditing)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
    }

    // MARK: - Filter Bar

    private var filterBarView: some View {
        HStack(spacing: Spacing.md) {
            Picker("Filter", selection: $filter) {
                ForEach(TapBenchmarkFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search taps, branches, URLs…", text: $searchFilter)
                    .textFieldStyle(.plain)

                if !searchFilter.isEmpty {
                    Button {
                        searchFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 240)
        }
    }

    // MARK: - Content Canvas

    private var contentCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                overviewBanner
                tapsListSection
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: - Overview Banner

    private var overviewBanner: some View {
        HStack(spacing: Spacing.md) {
            metricCard(
                title: "Installed Taps",
                value: "\(allReports.count)",
                icon: "square.3.layers.3d.down.forward",
                color: .blue
            )

            metricCard(
                title: "Avg Latency",
                value: averageLatencyMs != nil ? String(format: "%.0f ms", averageLatencyMs!) : "—",
                icon: "gauge.with.needle.fill",
                color: (averageLatencyMs ?? 0) > 400 ? .orange : .green
            )

            metricCard(
                title: "Behind Upstream",
                value: "\(outdatedCount)",
                icon: "arrow.triangle.pull",
                color: outdatedCount > 0 ? .orange : .secondary
            )

            metricCard(
                title: "High Latency",
                value: "\(highLatencyCount)",
                icon: "network.badge.shield.half.filled",
                color: highLatencyCount > 0 ? .yellow : .secondary
            )

            metricCard(
                title: "Shallow Clones",
                value: "\(shallowCount)",
                icon: "square.stack.3d.down.right",
                color: shallowCount > 0 ? .yellow : .secondary
            )
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Taps List

    private var tapsListSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Tapped Repositories (\(filteredReports.count))")
                    .font(.headline)
                Spacer()
                if let lastAudit = healthManager.lastAuditDate {
                    Text("Audited \(lastAudit.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if filteredReports.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No taps match the selected filter.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(filteredReports) { report in
                    tapCard(report: report)
                }
            }
        }
    }

    // MARK: - Tap Card

    private func tapCard(report: TapHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card Header
            HStack(spacing: 8) {
                Image(systemName: "square.3.layers.3d.down.forward")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(report.isOfficial ? Color.blue : Color.purple)

                Text(report.tapName)
                    .font(.headline)

                if report.isOfficial {
                    Text("Official")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }

                // Transport Protocol Pill
                HStack(spacing: 3) {
                    Image(systemName: report.transportProtocol.systemImage)
                    Text(report.transportProtocol.rawValue)
                }
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)

                // Latency Badge
                HStack(spacing: 3) {
                    Circle()
                        .fill(report.latencyColor)
                        .frame(width: 6, height: 6)
                    Text(report.formattedLatency)
                }
                .font(.caption2.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(report.latencyColor.opacity(0.12), in: Capsule())
                .foregroundStyle(report.latencyColor)

                Spacer()

                // Status Badge
                HStack(spacing: 4) {
                    Image(systemName: report.status.iconName)
                    Text(report.status.rawValue)
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(report.status.color.opacity(0.12), in: Capsule())
                .foregroundStyle(report.status.color)
            }

            // Card Body (Metadata & Inventory)
            HStack(spacing: 16) {
                if let branch = report.branch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.secondary)
                        Text(branch)
                            .font(.caption.monospaced())
                    }
                }

                if let head = report.headCommit {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                        Text(head)
                            .font(.caption.monospaced())
                    }
                }

                if let dateStr = report.lastCommitDateString {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text(dateStr)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("\(report.formulaCount) formulae")
                    Text("•")
                    Text("\(report.caskCount) casks")
                    if report.commandCount > 0 {
                        Text("•")
                        Text("\(report.commandCount) cmds")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Diagnostic callouts if any
            if report.hasCommitLag {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.pull")
                        .foregroundStyle(.orange)
                    Text("Behind upstream origin by \(report.commitLagBehind) commit\(report.commitLagBehind == 1 ? "" : "s"). Sync recommended.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            if report.isShallow {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.down.right")
                        .foregroundStyle(.yellow)
                    Text("Shallow git clone detected (.git/shallow). Run 'brew tap --repair \(report.tapName)' to fetch full git history.")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            if let remote = report.remoteURL {
                HStack(spacing: 4) {
                    Text(remote)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button {
                        healthManager.copyToClipboard(remote)
                        showToast("Copied remote URL to clipboard.")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Action Buttons
            HStack(spacing: 8) {
                Button {
                    Task {
                        let res = await healthManager.syncTap(tapName: report.tapName, prefix: effectivePrefix)
                        showToast(res.message)
                    }
                } label: {
                    Label("Sync Tap", systemImage: "arrow.triangle.pull")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(healthManager.isOperating)

                Button {
                    Task {
                        let res = await healthManager.repairTap(tapName: report.tapName, prefix: effectivePrefix, manager: manager)
                        showToast(res.message)
                    }
                } label: {
                    Label("Repair", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(healthManager.isOperating)

                if report.canSwitchProtocol {
                    Button {
                        tapToSwitchProtocol = report
                    } label: {
                        Label(
                            report.transportProtocol == .https ? "Switch to SSH" : "Switch to HTTPS",
                            systemImage: report.transportProtocol == .https ? "key.fill" : "lock.shield.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(healthManager.isOperating)
                }

                Button {
                    Task {
                        let ms = await healthManager.benchmarkLatency(for: report.tapName)
                        if let ms {
                            showToast("Latency: \(String(format: "%.0f ms", ms))")
                        } else {
                            showToast("Latency probe timed out.")
                        }
                    }
                } label: {
                    Label("Test Latency", systemImage: "gauge.with.needle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Untap", role: .destructive) {
                    tapToUntap = report
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(healthManager.isOperating)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(report.status != .healthy ? report.status.color.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Empty & Loading States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Auditing Homebrew taps and benchmarking upstream latencies…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTapsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.3.layers.3d.down.forward")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Homebrew Taps Detected")
                .font(.title3.bold())
            Text("Taps are third-party or official git repositories providing custom Homebrew formulae and casks.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Scan Local Taps") {
                refreshAudit()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func refreshAudit() {
        healthManager.auditAllTaps(taps: manager.taps, prefix: effectivePrefix)
        Task {
            await healthManager.benchmarkAllLatencies()
        }
    }

    private func batchSyncOutdated() {
        isSyncingAll = true
        Task {
            let res = await healthManager.batchSyncAllOutdatedTaps(prefix: effectivePrefix)
            isSyncingAll = false
            showToast("Synced \(res.succeeded.count) tap\(res.succeeded.count == 1 ? "" : "s").")
        }
    }

    private func performUntap(tapName: String) {
        manager.untap(name: tapName) { success in
            if success {
                showToast("Untapped '\(tapName)'.")
                healthManager.reports.removeValue(forKey: tapName)
                manager.refresh()
            } else {
                showToast("Failed to untap '\(tapName)'.")
            }
        }
    }

    private func performSwitchProtocol(tapName: String, to target: TapTransportProtocol) {
        Task {
            let res = await healthManager.switchProtocol(tapName: tapName, to: target, prefix: effectivePrefix)
            showToast(res.message)
        }
    }

    private func showToast(_ message: String) {
        withAnimation {
            statusToast = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if statusToast == message {
                    statusToast = nil
                }
            }
        }
    }
}
