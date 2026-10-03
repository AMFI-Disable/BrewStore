import AppKit
import SwiftUI

enum BottleAuditFilter: String, CaseIterable, Identifiable {
    case all = "All Packages"
    case issuesOnly = "Integrity Issues"
    case verified = "Verified Bottles"
    case fromSource = "Built From Source"

    var id: String { rawValue }
}

struct BottleIntegrityAuditorView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var auditor = BrewStoreBottleIntegrityAuditor.shared
    @Environment(\.dismiss) private var dismiss

    @State private var filter: BottleAuditFilter = .all
    @State private var searchFilter: String = ""
    @State private var expandedPackageID: String?
    @State private var packageToReinstall: BottleIntegrityReport?
    @State private var statusToast: String?
    @State private var copiedHashID: String?

    private var effectivePrefix: String {
        manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
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
                if auditor.isAuditing && auditor.summary == nil {
                    loadingView
                } else if let summary = auditor.summary {
                    contentCanvas(summary: summary)
                } else {
                    initialAuditView
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
        .frame(minWidth: 740, idealWidth: 820, minHeight: 540, idealHeight: 620)
        .onAppear {
            if auditor.summary == nil {
                auditor.auditAllInstalled(prefix: effectivePrefix, packages: manager.packages)
            }
        }
        .confirmationDialog(
            "Reinstall \(packageToReinstall?.packageName ?? "Bottle")?",
            isPresented: Binding(
                get: { packageToReinstall != nil },
                set: { if !$0 { packageToReinstall = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Reinstall Bottle (brew reinstall --force-bottle)", role: .destructive) {
                if let pkg = packageToReinstall {
                    Task {
                        let res = await auditor.reinstallBottle(packageID: pkg.packageID, prefix: effectivePrefix, manager: manager)
                        showToast(res.message)
                        auditor.auditAllInstalled(prefix: effectivePrefix, packages: manager.packages)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace the current installation of '\(packageToReinstall?.packageID ?? "")' with a clean, verified bottle downloaded directly from Homebrew's official binary mirror.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Bottle Integrity & SHA-256 Auditor")
                        .font(.title2.bold())

                    if auditor.isAuditing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text("Verify official cryptographic signatures, inspect installed Mach-O binaries, and detect corrupted or tampered Cellar files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                auditor.auditAllInstalled(prefix: effectivePrefix, packages: manager.packages)
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(auditor.isAuditing)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Filter Bar

    private var filterBarView: some View {
        HStack(spacing: 12) {
            Picker("Filter", selection: $filter) {
                ForEach(BottleAuditFilter.allCases) { item in
                    HStack(spacing: 4) {
                        Text(item.rawValue)
                        if let summary = auditor.summary {
                            switch item {
                            case .all:
                                Text("(\(summary.reports.count))")
                            case .issuesOnly:
                                Text("(\(summary.totalIssuesCount))")
                            case .verified:
                                Text("(\(summary.verifiedCount))")
                            case .fromSource:
                                Text("(\(summary.builtFromSourceCount))")
                            }
                        }
                    }
                    .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search formula…", text: $searchFilter)
                    .textFieldStyle(.plain)
                    .frame(width: 170)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Content Canvas

    private func filteredReports(from summary: SystemBottleAuditSummary) -> [BottleIntegrityReport] {
        summary.reports.filter { rep in
            let matchesSearch: Bool
            if searchFilter.isEmpty {
                matchesSearch = true
            } else {
                matchesSearch = rep.packageName.localizedCaseInsensitiveContains(searchFilter) ||
                    rep.packageID.localizedCaseInsensitiveContains(searchFilter)
            }
            guard matchesSearch else { return false }

            switch filter {
            case .all:
                return true
            case .issuesOnly:
                return rep.hasIntegrityIssue
            case .verified:
                return rep.status == .verifiedBottle
            case .fromSource:
                return rep.status == .builtFromSource
            }
        }
    }

    @ViewBuilder
    private func contentCanvas(summary: SystemBottleAuditSummary) -> some View {
        let filtered = filteredReports(from: summary)

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                overviewBanner(summary: summary)

                if filtered.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No matching packages found.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(filtered, id: \.packageID) { report in
                            packageCard(report: report)
                        }
                    }
                }
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: - Overview Banner

    @ViewBuilder
    private func overviewBanner(summary: SystemBottleAuditSummary) -> some View {
        let isHealthy = summary.totalIssuesCount == 0
        let themeColor: Color = isHealthy ? .green : .orange
        let bannerIcon = isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"

        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(themeColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: bannerIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(themeColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                if isHealthy {
                    Text("All \(summary.reports.count) Formulae Cryptographically Sound")
                        .font(.headline.bold())
                    Text("Every installed bottle matches its official Homebrew receipt and declared binaries are fully intact.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(summary.totalIssuesCount) Package\(summary.totalIssuesCount == 1 ? "" : "s") Require Attention")
                        .font(.headline.bold())
                    Text("Found \(summary.corruptedCount) corrupted or missing binary installations and \(summary.unmanagedCount) unmanaged or missing receipts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                statusMetricBadge(title: "Verified", count: summary.verifiedCount, color: .green)
                if summary.builtFromSourceCount > 0 {
                    statusMetricBadge(title: "Source", count: summary.builtFromSourceCount, color: .purple)
                }
                if summary.totalIssuesCount > 0 {
                    statusMetricBadge(title: "Issues", count: summary.totalIssuesCount, color: .red)
                }
            }
        }
        .padding(Spacing.md)
        .background(themeColor.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.panel))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(themeColor.opacity(0.2), lineWidth: 1)
        )
    }

    private func statusMetricBadge(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Package Card

    @ViewBuilder
    private func packageCard(report: BottleIntegrityReport) -> some View {
        let isExpanded = expandedPackageID == report.packageID

        VStack(alignment: .leading, spacing: 8) {
            packageCardHeader(report: report, isExpanded: isExpanded)

            if isExpanded {
                Divider()
                    .padding(.vertical, 2)
                expandedBinaryChecksumsSection(report: report)
            }
        }
        .padding(Spacing.md)
        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: Radius.panel))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(report.hasIntegrityIssue ? Color.red.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func packageCardHeader(report: BottleIntegrityReport, isExpanded: Bool) -> some View {
        let color = statusColor(report.status)

        HStack(alignment: .center, spacing: 10) {
            Image(systemName: report.status.icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(report.packageName)
                        .font(.headline)
                    Text("v\(report.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(report.status.rawValue)
                        .font(.caption2.bold())
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12), in: Capsule())

                    if let arch = report.bottleArch {
                        Text(arch)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                if let reason = report.failureReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let compiler = report.compiler {
                    Text("Compiled with \(compiler) • \(report.installedFilesCount) files in Cellar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedPackageID = isExpanded ? nil : report.packageID
                    }
                } label: {
                    Label(isExpanded ? "Hide Binaries" : "Inspect Checksums", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                if report.hasIntegrityIssue {
                    Button {
                        packageToReinstall = report
                    } label: {
                        Label("Reinstall Bottle", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(auditor.operatingPackageID != nil)
                } else {
                    Button {
                        packageToReinstall = report
                    } label: {
                        Label("Reinstall Bottle", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .disabled(auditor.operatingPackageID != nil)
                }
            }
        }
    }

    @ViewBuilder
    private func expandedBinaryChecksumsSection(report: BottleIntegrityReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sha = report.bottleSHA256 {
                HStack(spacing: 6) {
                    Text("Bottle SHA-256:")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(sha)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button {
                        auditor.copyToClipboard(sha)
                        copiedHashID = report.packageID
                        showToast("Copied bottle SHA-256")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if copiedHashID == report.packageID {
                                copiedHashID = nil
                            }
                        }
                    } label: {
                        Image(systemName: copiedHashID == report.packageID ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }

            if report.binaryChecksums.isEmpty {
                Text("No executable binaries discovered in bin/ or declared linkage files.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                Text("Mach-O Binaries & Cryptographic Hashes (\(report.binaryChecksums.count))")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    ForEach(report.binaryChecksums) { bin in
                        binaryRow(bin: bin)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func binaryRow(bin: BinaryChecksumItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(bin.relativePath)
                .font(.system(size: 11, weight: .medium, design: .monospaced))

            Text(bin.formattedSize)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Text(bin.sha256)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .trailing)

            Button {
                auditor.copyToClipboard(bin.sha256)
                showToast("Copied hash for \(bin.relativePath)")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    private func statusColor(_ status: BottleIntegrityStatus) -> Color {
        switch status {
        case .verifiedBottle: return .green
        case .builtFromSource: return .purple
        case .unmanagedOrManual: return .orange
        case .corruptedOrTampered: return .red
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Computing cryptographic checksums and verifying Cellar files…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var initialAuditView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Ready to Audit Bottle Integrity")
                .font(.headline)
            Button("Run System Audit") {
                auditor.auditAllInstalled(prefix: effectivePrefix, packages: manager.packages)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func showToast(_ message: String) {
        withAnimation {
            statusToast = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if statusToast == message {
                    statusToast = nil
                }
            }
        }
    }
}
