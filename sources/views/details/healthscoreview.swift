import AppKit
import SwiftUI

struct HealthScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var optimizer = BrewStoreHealthOptimizer()
    @StateObject private var doctorManager = BrewStoreDependencyDoctorManager.shared
    @State private var showingCVESecuritySheet = false
    @State private var pendingHealthIssue: HealthIssueItem?
    @State private var showingAutoHealConfirmation = false

    private var doctorDiagnostics: [BrewStoreDoctorDiagnostic] {
        BrewStoreDoctorParser.parse(manager.outputLog)
    }

    var showHeader: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                headerBar
                Divider()
            }
            contentBody
        }
        .frame(minWidth: showHeader ? 720 : nil, minHeight: showHeader ? 560 : nil)
        .onAppear {
            optimizer.evaluateHealth(manager: manager, doctorDiagnostics: doctorDiagnostics)
            doctorManager.diagnose(manager: manager)
        }
        .sheet(isPresented: $showingCVESecuritySheet) {
            CVESecurityView(manager: manager)
        }
        .confirmationDialog(
            "Repair Common Issues?",
            isPresented: $showingAutoHealConfirmation,
            titleVisibility: .visible
        ) {
            Button("Repair Issues") {
                doctorManager.autoHealToolchain(manager: manager)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will repair broken symlinks ('brew link --overwrite'), prune orphaned dependencies ('brew autoremove'), and purge stale download caches.")
        }
        .confirmationDialog(
            pendingHealthIssue?.actionTitle ?? "Confirm Action",
            isPresented: Binding(get: { pendingHealthIssue != nil }, set: {
                if !$0 {
                    pendingHealthIssue = nil
                }
            }),
            titleVisibility: .visible
        ) {
            if let issue = pendingHealthIssue {
                Button(issue.actionTitle, role: issue.id == "stale-locks" ? .destructive : nil) {
                    handleIssueAction(issue.id)
                    pendingHealthIssue = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingHealthIssue = nil
                }
            }
        } message: {
            if let issue = pendingHealthIssue {
                Text(healthConfirmationMessage(for: issue))
            }
        }
    }

    @ViewBuilder
    private var headerBar: some View {
        if showHeader {
            HStack(spacing: Spacing.md) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                    .padding(8)
                    .background(Color.pink.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Homebrew Health & Diagnostics").font(.title2.bold())
                    Text("Check package status, fix broken symlinks, remove unused dependencies, and reclaim disk space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingCVESecuritySheet = true
                } label: {
                    Label("Security Audit", systemImage: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    optimizer.evaluateHealth(manager: manager, doctorDiagnostics: doctorDiagnostics)
                    doctorManager.diagnose(manager: manager)
                } label: {
                    Label("Re-Evaluate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(optimizer.isEvaluating || doctorManager.isDiagnosing || manager.isOperating)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(Color.secondary.opacity(0.04))
        }
    }

    private var contentBody: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Repair In Progress Banner
                if doctorManager.isHealing, let msg = doctorManager.healStatusMessage {
                    HStack(spacing: Spacing.md) {
                        ProgressView().controlSize(.small)
                        Text(msg).font(.subheadline.bold())
                        Spacer()
                    }
                    .padding(Spacing.md)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }

                if optimizer.isEvaluating || doctorManager.isDiagnosing {
                    ProgressView("Analyzing package dependencies, cache, and diagnostics…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let assessment = optimizer.assessment {
                    scoreHeroCard(assessment: assessment)
                    diagnosticsOverviewBar(assessment: assessment)

                    // Diagnostics Card
                    if let docReport = doctorManager.report, !docReport.issues.isEmpty {
                        toolchainDoctorSection(report: docReport)
                    }

                    if !assessment.issues.isEmpty {
                        issuesList(issues: assessment.issues)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
    }

    private func toolchainDoctorSection(report: ToolchainDiagnosisReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Diagnostics & Fixes (\(report.issues.count) Issues Found)", systemImage: "wrench.and.screwdriver.fill")
                    .font(.headline)
                Spacer()
                Button {
                    showingAutoHealConfirmation = true
                } label: {
                    Label("Repair Issues", systemImage: "wrench.and.screwdriver.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
                .disabled(doctorManager.isHealing || manager.isOperating)
            }

            ForEach(report.issues) { issue in
                HStack(spacing: 14) {
                    Image(systemName: issueKindIcon(issue.kind))
                        .foregroundStyle(issueKindColor(issue.kind))
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title).font(.subheadline.bold())
                        Text(issue.description).font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(issue.recommendedAction) {
                        doctorManager.fixIssue(issue, manager: manager)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(doctorManager.isHealing || manager.isOperating)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.18), lineWidth: 1))
    }

    private func issueKindIcon(_ kind: ToolchainIssue.IssueKind) -> String {
        switch kind {
        case .orphan: "scissors"
        case .unlinked: "link.badge.plus"
        case .missing: "exclamationmark.triangle.fill"
        case .doctor: "stethoscope"
        }
    }

    private func issueKindColor(_ kind: ToolchainIssue.IssueKind) -> Color {
        switch kind {
        case .orphan: .orange
        case .unlinked: .blue
        case .missing: .red
        case .doctor: .yellow
        }
    }

    private func scoreHeroCard(assessment: HomebrewHealthAssessment) -> some View {
        HStack(spacing: 24) {
            // Circular Gauge
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                    .frame(width: 96, height: 96)

                Circle()
                    .trim(from: 0, to: CGFloat(assessment.score) / 100.0)
                    .stroke(scoreColor(assessment.score), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(assessment.score)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("SCORE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Grade: \(assessment.grade)")
                        .font(.title3.bold())
                        .foregroundStyle(scoreColor(assessment.score))
                    Text(scoreSubtitle(assessment.score))
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(scoreColor(assessment.score).opacity(0.12), in: Capsule())
                        .foregroundStyle(scoreColor(assessment.score))
                }

                Text(assessment.statusSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: Spacing.sm) {
                    Button {
                        optimizer.optimizeAll(manager: manager)
                    } label: {
                        Label("Optimize System", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .disabled(manager.isOperating)

                    if !showHeader {
                        Button {
                            showingCVESecuritySheet = true
                        } label: {
                            Label("Security Audit", systemImage: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            optimizer.evaluateHealth(manager: manager, doctorDiagnostics: doctorDiagnostics)
                            doctorManager.diagnose(manager: manager)
                        } label: {
                            Label("Re-Evaluate", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(optimizer.isEvaluating || doctorManager.isDiagnosing || manager.isOperating)
                    }
                }
            }
            Spacer()
        }
        .padding(Spacing.lg)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func diagnosticsOverviewBar(assessment: HomebrewHealthAssessment) -> some View {
        HStack(spacing: 12) {
            metricBox(
                title: "OUTDATED",
                value: "\(assessment.outdatedCount)",
                subtitle: assessment.outdatedCount == 0 ? "Up to date" : "Updates pending",
                icon: "arrow.triangle.2.circlepath",
                color: assessment.outdatedCount == 0 ? .green : .orange
            )

            metricBox(
                title: "CACHE USAGE",
                value: ByteCountFormatter.string(fromByteCount: assessment.cacheSizeBytes, countStyle: .file),
                subtitle: "Cached downloads",
                icon: "internaldrive",
                color: .blue
            )

            metricBox(
                title: "DOCTOR ISSUES",
                value: "\(assessment.doctorIssueCount)",
                subtitle: assessment.doctorIssueCount == 0 ? "No issues" : "Warnings found",
                icon: "stethoscope",
                color: assessment.doctorIssueCount == 0 ? .green : .orange
            )
        }
    }

    private func issuesList(issues: [HealthIssueItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended Actions").font(.headline)

            ForEach(issues) { issue in
                HStack(spacing: 14) {
                    Image(systemName: severityIcon(issue.severity))
                        .foregroundStyle(severityColor(issue.severity))
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title).font(.headline)
                        Text(issue.description).font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(issue.actionTitle) {
                        pendingHealthIssue = issue
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func handleIssueAction(_ issueID: String) {
        if issueID == "stale-locks" {
            manager.clearLocks()
            optimizer.evaluateHealth(manager: manager, doctorDiagnostics: doctorDiagnostics)
        } else if issueID == "outdated-packages" {
            manager.upgradeAllPackages()
        } else if issueID == "stale-cache" {
            manager.cleanup()
        } else {
            manager.runDoctor()
        }
    }

    private func healthConfirmationMessage(for issue: HealthIssueItem) -> String {
        switch issue.id {
        case "stale-locks":
            "Clearing locks terminates any stuck background workers and deletes lock files in var/homebrew/locks so operations can proceed. Make sure no Terminal operations are active."
        case "outdated-packages":
            "This will upgrade all installed software versions to their latest stable releases."
        case "stale-cache":
            "This will purge stale download bottles and tarballs to reclaim disk space."
        default:
            "Run diagnostics to identify configuration issues and generate fix recommendations."
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 {
            return .green
        }
        if score >= 75 {
            return .blue
        }
        if score >= 60 {
            return .orange
        }
        return .red
    }

    private func scoreSubtitle(_ score: Int) -> String {
        if score >= 90 {
            return "Optimal"
        }
        if score >= 75 {
            return "Good"
        }
        return "Action Needed"
    }

    private func severityIcon(_ severity: String) -> String {
        switch severity {
        case "critical": "exclamationmark.triangle.fill"
        case "warning": "exclamationmark.circle.fill"
        default: "info.circle.fill"
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "critical": .red
        case "warning": .orange
        default: .blue
        }
    }

    private func metricBox(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
            }
            Text(value)
                .font(.title2.bold())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
