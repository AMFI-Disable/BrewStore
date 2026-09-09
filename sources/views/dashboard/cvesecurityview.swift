import AppKit
import SwiftUI

struct CVESecurityView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @StateObject private var scanner = BrewStoreCVESecurityScanner.shared

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if scanner.isScanning {
                scanningProgressView
            } else if let error = scanner.scanError {
                errorRecoveryView(error: error)
            } else if let report = scanner.report {
                reportContentView(report: report)
            } else {
                emptyPromptView
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            if scanner.report == nil, !scanner.isScanning, scanner.scanError == nil {
                scanner.scanSecurity(manager: manager)
            }
        }
    }

    private var scanningProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Checking installed packages for security advisories…")
                .font(.headline)
            Text("Checking installed packages for security vulnerabilities, deprecations, and configuration warnings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                scanner.cancelScan()
            } label: {
                Label("Cancel Scan", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorRecoveryView(error: CVEScanError) -> some View {
        VStack(spacing: 20) {
            Image(systemName: errorIcon(error))
                .font(.system(size: 48))
                .foregroundStyle(errorColor(error))
                .padding(16)
                .background(errorColor(error).opacity(0.12), in: Circle())

            VStack(spacing: 6) {
                Text(errorTitle(error))
                    .font(.title2.bold())

                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let suggestion = error.recoverySuggestion {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.orange)
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
                }
            }

            // Recovery Action Buttons
            HStack(spacing: 12) {
                Button {
                    scanner.scanSecurity(manager: manager)
                } label: {
                    Label(error == .cancelled ? "Restart Security Audit" : "Retry Security Audit", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                if case .commandFailed = error {
                    Button {
                        dismiss()
                        manager.runDoctor()
                    } label: {
                        Label("Run Homebrew Doctor", systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                if scanner.report != nil {
                    Button("View Cached Report") {
                        scanner.scanError = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.red)
                .padding(8)
                .background(Color.red.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Security Audit").font(.title2.bold())
                    statusBadge
                }
                Text("Audit installed packages for security vulnerabilities, deprecated formulae, and warnings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if scanner.isScanning {
                Button("Cancel Scan") {
                    scanner.cancelScan()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    scanner.scanSecurity(manager: manager)
                } label: {
                    Label("Run Audit", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.isOperating)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
        .background(Color.secondary.opacity(0.04))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if scanner.isScanning {
            Text("Scanning…")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.15), in: Capsule())
                .foregroundStyle(.blue)
        } else if scanner.scanError != nil {
            Text("Scan Issue")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(.orange)
        } else if let report = scanner.report {
            Text("Score: \(report.securityScore)/100")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(report.securityScore >= 90 ? Color.green.opacity(0.15) : Color.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(report.securityScore >= 90 ? Color.green : Color.orange)
        }
    }

    private var emptyPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("No Security Scan Performed")
                .font(.title2.bold())

            Button {
                scanner.scanSecurity(manager: manager)
            } label: {
                Label("Start Security Audit", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reportContentView(report: CVESecurityReport) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Score and Metric Gauges
                HStack(spacing: 16) {
                    metricBox(title: "SECURITY SCORE", value: "\(report.securityScore)/100", subtitle: report.securityScore >= 90 ? "Secure" : "Action Needed", color: report.securityScore >= 90 ? .green : .orange, icon: "shield.fill")
                    metricBox(title: "CRITICAL / CVE", value: "\(report.criticalIssues.count)", subtitle: "Known CVEs", color: report.criticalIssues.isEmpty ? .green : .red, icon: "exclamationmark.triangle.fill")
                    metricBox(title: "HIGH / DEPRECATED", value: "\(report.highIssues.count)", subtitle: "Deprecated formulae", color: report.highIssues.isEmpty ? .green : .orange, icon: "exclamationmark.circle.fill")
                    metricBox(title: "TOTAL CHECKED", value: "\(report.totalChecked)", subtitle: "Installed packages", color: .blue, icon: "shippingbox.fill")
                }

                if report.isClean {
                    ContentUnavailableView(
                        "No Security Issues Found",
                        systemImage: "checkmark.shield.fill",
                        description: Text("All installed packages passed audit checks without known security warnings.")
                    )
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Security Issues & Recommendations (\(report.issues.count))")
                            .font(.headline)

                        ForEach(report.issues) { issue in
                            HStack(spacing: 12) {
                                Image(systemName: issue.severity == .critical ? "exclamationmark.triangle.fill" : (issue.severity == .high ? "exclamationmark.circle.fill" : "info.circle.fill"))
                                    .foregroundStyle(severityColor(issue.severity))
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(issue.packageName).font(.headline)
                                        Text(issue.severity.rawValue)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(severityColor(issue.severity).opacity(0.12), in: Capsule())
                                            .foregroundStyle(severityColor(issue.severity))
                                        if let cve = issue.cveIdentifier {
                                            Text(cve)
                                                .font(.caption2.monospaced().bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Color.red.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    Text(issue.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if let pkg = manager.packages.first(where: { $0.id.lowercased() == issue.packageName.lowercased() }) {
                                    Button(issue.remediationAction) {
                                        manager.perform(package: pkg, action: .upgrade)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(manager.isOperating)
                                }
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func severityColor(_ severity: CVESeverity) -> Color {
        switch severity {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .info: .blue
        }
    }

    private func metricBox(title: String, value: String, subtitle: String, color: Color, icon: String) -> some View {
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
                .foregroundStyle(color)
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

    private func errorIcon(_ error: CVEScanError) -> String {
        switch error {
        case .timeout: "clock.badge.exclamationmark"
        case .cancelled: "slash.circle"
        case let .retryable(_, isLock): isLock ? "lock.shield" : "arrow.clockwise.circle.fill"
        case .commandFailed: "exclamationmark.triangle.fill"
        case .homebrewUnavailable: "xmark.octagon.fill"
        case .malformedOutput: "doc.badge.ellipsis"
        }
    }

    private func errorColor(_ error: CVEScanError) -> Color {
        switch error {
        case .timeout: .orange
        case .cancelled: .secondary
        case .retryable: .orange
        case .commandFailed: .red
        case .homebrewUnavailable: .red
        case .malformedOutput: .orange
        }
    }

    private func errorTitle(_ error: CVEScanError) -> String {
        switch error {
        case .timeout: "Security Audit Timed Out"
        case .cancelled: "Security Audit Cancelled"
        case let .retryable(_, isLock): isLock ? "Homebrew Lock In Use" : "Temporary Network Issue"
        case .commandFailed: "Security Audit Failed"
        case .homebrewUnavailable: "Homebrew Unavailable"
        case .malformedOutput: "Corrupted Audit Data"
        }
    }
}
