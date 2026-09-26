import AppKit
import SwiftUI

struct HealthScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var optimizer = BrewStoreHealthOptimizer()
    @StateObject private var doctorManager = BrewStoreDependencyDoctorManager.shared
    @StateObject private var remediationManager = BrewStoreDoctorRemediationManager.shared
    @State private var showingCVESecuritySheet = false
    @State private var pendingHealthIssue: HealthIssueItem?
    @State private var showingAutoHealConfirmation = false
    @State private var showingBatchRemediationConfirmation = false
    @State private var dryRunDiagnostic: BrewStoreDoctorDiagnostic?
    @State private var dryRunOutput: String?
    @State private var isExecutingDryRun = false
    @State private var copiedDiagnosticID: String?

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
        .sheet(item: $dryRunDiagnostic) { diag in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Dry-Run Simulation", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.headline)
                    Spacer()
                    Button("Done") { dryRunDiagnostic = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Text("Diagnostic: \(diag.title)").font(.subheadline.bold())
                if let cmd = diag.dryRunCommand ?? diag.autoFixCommand {
                    Text("Simulating command: `\(cmd)`").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Divider()
                if isExecutingDryRun {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Executing dry-run check…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ScrollView {
                        Text(dryRunOutput ?? "No simulation output recorded.")
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                    .frame(minHeight: 120, maxHeight: 220)
                }
                HStack {
                    Spacer()
                    if diag.autoFixCommand != nil {
                        Button("Apply Real Remediation") {
                            let target = diag
                            dryRunDiagnostic = nil
                            remediationManager.executeDiagnosticRemediation(diagnostic: target, isDryRun: false, manager: manager) { _, _ in
                                optimizer.evaluateHealth(manager: manager, doctorDiagnostics: doctorDiagnostics)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isExecutingDryRun || manager.isOperating)
                    }
                }
            }
            .padding(20)
            .frame(width: 540, height: 380)
        }
        .confirmationDialog(
            "Auto-Remediate All Safe Issues?",
            isPresented: $showingBatchRemediationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Execute Safe Repairs") {
                remediationManager.batchRemediateSafe(diagnostics: doctorDiagnostics, manager: manager) { _, _ in
                    optimizer.evaluateHealth(manager: manager, doctorDiagnostics: doctorDiagnostics)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will safely resolve issues flagged as Safe Auto-Remediation (e.g. relinking non-conflicting Cellar binaries, scrubbing dangling symlinks, and clearing download caches).")
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

                    if !doctorDiagnostics.isEmpty {
                        icuDiagnosticsSection(diagnostics: doctorDiagnostics)
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
                    doctorManager.pruneDanglingSymlinks(manager: manager)
                } label: {
                    Label("Prune Symlinks", systemImage: "link.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(doctorManager.isHealing || manager.isOperating)

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
    }

    private func icuDiagnosticsSection(diagnostics: [BrewStoreDoctorDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Homebrew ICU: Autonomous Doctor (\(diagnostics.count))", systemImage: "stethoscope.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                let safeCount = diagnostics.filter { $0.isAutoFixable && $0.safetyLevel == .safeToAutoFix }.count
                if safeCount > 0 {
                    Button {
                        showingBatchRemediationConfirmation = true
                    } label: {
                        Label("Auto-Remediate All Safe (\(safeCount))", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                    .disabled(remediationManager.isBatchRemediating || manager.isOperating)
                }
            }

            if remediationManager.isBatchRemediating {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(remediationManager.batchStatusMessage ?? "Auto-remediating issues…")
                            .font(.caption.bold())
                        Spacer()
                        Text("\(Int(remediationManager.batchRemediationProgress * 100))%")
                            .font(.caption.monospaced())
                    }
                    ProgressView(value: remediationManager.batchRemediationProgress, total: 1.0)
                        .progressViewStyle(.linear)
                }
                .padding(10)
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            ForEach(diagnostics) { diag in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label(diag.faultDomain.rawValue, systemImage: diag.faultDomain.iconName)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())

                        Text(diag.safetyLevel.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(safetyColor(diag.safetyLevel).opacity(0.14), in: Capsule())
                            .foregroundStyle(safetyColor(diag.safetyLevel))

                        Spacer()

                        if diag.severity == .clean {
                            Label("Clean", systemImage: "checkmark.circle.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.green)
                        } else if diag.severity == .error {
                            Label("Critical Fault", systemImage: "xmark.octagon.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.red)
                        } else {
                            Label("Degraded / Warning", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.orange)
                        }
                    }

                    Text(diag.title).font(.subheadline.bold())
                    Text(diag.message).font(.caption).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Color.blue)
                                .font(.caption2)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("Why this matters:")
                                        .font(.caption2.bold())
                                    Text(diag.impactExplanation)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 4) {
                                    Text("Potential fallout:")
                                        .font(.caption2.bold())
                                    Text(diag.potentialFallout)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 8) {
                        if diag.dryRunCommand != nil || diag.autoFixCommand != nil {
                            Button {
                                dryRunDiagnostic = diag
                                isExecutingDryRun = true
                                dryRunOutput = nil
                                remediationManager.executeDiagnosticRemediation(diagnostic: diag, isDryRun: true, manager: manager) { _, output in
                                    dryRunOutput = output
                                    isExecutingDryRun = false
                                }
                            } label: {
                                Label("Dry-Run Preview", systemImage: "play.circle")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(manager.isOperating || remediationManager.isFixing)
                        }

                        if diag.isAutoFixable, diag.autoFixCommand != nil {
                            Button {
                                remediationManager.executeDiagnosticRemediation(diagnostic: diag, isDryRun: false, manager: manager) { _, _ in
                                    optimizer.evaluateHealth(manager: manager, doctorDiagnostics: doctorDiagnostics)
                                }
                            } label: {
                                if remediationManager.activeFixIssueID == diag.id {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Label("Auto-Remediate", systemImage: "wand.and.stars")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(diag.safetyLevel == .safeToAutoFix ? Color.green : Color.purple)
                            .controlSize(.small)
                            .disabled(manager.isOperating || remediationManager.isFixing)
                        } else if let suggested = diag.suggestedCommand {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(suggested, forType: .string)
                                copiedDiagnosticID = diag.id
                                Task {
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    if copiedDiagnosticID == diag.id { copiedDiagnosticID = nil }
                                }
                            } label: {
                                Label(copiedDiagnosticID == diag.id ? "Copied Command!" : "Copy Suggested Command", systemImage: copiedDiagnosticID == diag.id ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
            }
        }
        .padding(16)
        .background(Color.purple.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.15), lineWidth: 1))
    }

    private func safetyColor(_ safety: RemediationSafetyLevel) -> Color {
        switch safety {
        case .safeToAutoFix: .green
        case .requiresReview: .orange
        case .manualIntervention: .purple
        }
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

                    if (doctorManager.report?.issues.isEmpty == false) || !assessment.issues.isEmpty {
                        Button {
                            showingAutoHealConfirmation = true
                        } label: {
                            Label("Auto-Fix Issues", systemImage: "wrench.and.screwdriver.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.small)
                        .disabled(doctorManager.isHealing || manager.isOperating)
                    }

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
