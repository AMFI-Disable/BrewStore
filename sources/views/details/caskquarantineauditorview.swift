import AppKit
import SwiftUI

enum QuarantineFilter: String, CaseIterable, Identifiable {
    case all = "All Casks"
    case quarantined = "Quarantined"
    case clean = "Clean & Verified"
    case adHoc = "Ad-Hoc Signed"

    var id: String { rawValue }
}

struct CaskQuarantineAuditorView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var auditor = BrewStoreCaskQuarantineAuditor.shared
    @ObservedObject private var preferences = BrewStorePreferences.shared
    @Environment(\.dismiss) private var dismiss

    @State private var filter: QuarantineFilter = .all
    @State private var searchFilter: String = ""
    @State private var showingBatchClearConfirmation = false
    @State private var statusToast: String?
    @State private var expandedItemIDs: Set<String> = []

    private var filteredItems: [CaskQuarantineItem] {
        var list = auditor.auditedItems

        switch filter {
        case .all:
            break
        case .quarantined:
            list = list.filter { $0.status == .quarantined }
        case .clean:
            list = list.filter { $0.status == .clean }
        case .adHoc:
            list = list.filter { $0.status == .adHocSigned }
        }

        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.caskName.localizedCaseInsensitiveContains(query) ||
                $0.id.localizedCaseInsensitiveContains(query) ||
                ($0.signingAuthority?.localizedCaseInsensitiveContains(query) ?? false) ||
                ($0.teamIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    metricsOverviewBanner

                    policyCard

                    filterAndSearchBar

                    if auditor.isAuditing {
                        auditingProgressCard
                    }

                    if filteredItems.isEmpty {
                        emptyStateView
                    } else {
                        itemsListView
                    }
                }
                .padding(Spacing.lg)
            }

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
        .frame(minWidth: 800, idealWidth: 880, minHeight: 580, idealHeight: 660)
        .onAppear {
            if auditor.auditedItems.isEmpty {
                runAudit()
            }
        }
        .confirmationDialog(
            "Clear Quarantine on All Apps?",
            isPresented: $showingBatchClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Quarantine on \(auditor.summary.quarantinedCount) Apps", role: .destructive) {
                Task {
                    let result = await auditor.removeQuarantineAll(items: auditor.auditedItems)
                    showToast("Cleared quarantine from \(result.cleared) app\(result.cleared == 1 ? "" : "s").")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will strip the 'com.apple.quarantine' extended attribute from all quarantined Homebrew casks, allowing them to launch without Gatekeeper warnings.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Cask Quarantine & Gatekeeper Auditor")
                        .font(.title2.bold())

                    if auditor.isAuditing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("Audit extended quarantine attributes (com.apple.quarantine), code signatures, and Gatekeeper policies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                runAudit()
            } label: {
                Label("Re-Audit All", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(auditor.isAuditing)

            if auditor.summary.quarantinedCount > 0 {
                Button {
                    showingBatchClearConfirmation = true
                } label: {
                    Label("Clear All Quarantines (\(auditor.summary.quarantinedCount))", systemImage: "checkmark.shield.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(auditor.isAuditing)
            }

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
    }

    // MARK: - Metrics Banner

    private var metricsOverviewBanner: some View {
        let sum = auditor.summary
        return HStack(spacing: Spacing.md) {
            metricCard(
                title: "Total Audited",
                value: "\(sum.totalAudited)",
                icon: "app.badge.checkmark",
                color: .blue
            )

            metricCard(
                title: "Quarantined",
                value: "\(sum.quarantinedCount)",
                icon: "exclamationmark.shield.fill",
                color: sum.quarantinedCount > 0 ? .orange : .secondary
            )

            metricCard(
                title: "Clean & Verified",
                value: "\(sum.cleanCount)",
                icon: "checkmark.shield.fill",
                color: .green
            )

            metricCard(
                title: "Ad-Hoc / Custom",
                value: "\(sum.adHocCount)",
                icon: "signature",
                color: .purple
            )
        }
    }

    // MARK: - Policy Card

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .foregroundStyle(.secondary)
                Text("Homebrew Cask Quarantine Policy")
                    .font(.subheadline.bold())

                Spacer()

                Toggle("Skip Quarantine on Install (--no-quarantine)", isOn: $preferences.noQuarantineCaskOpts)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            HStack(alignment: .top, spacing: 8) {
                Text(preferences.noQuarantineCaskOpts ?
                     "Active: BrewStore passes '--no-quarantine' when installing casks to bypass macOS Gatekeeper quarantine prompts." :
                     "Default: macOS Gatekeeper attaches 'com.apple.quarantine' to downloaded casks, prompting verification on first launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    let cmd = "export HOMEBREW_CASK_OPTS=\"--no-quarantine\""
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                    showToast("Copied HOMEBREW_CASK_OPTS to clipboard.")
                } label: {
                    Label("Copy Shell Export", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(Spacing.md)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Filter and Search Bar

    private var filterAndSearchBar: some View {
        HStack(spacing: 12) {
            Picker("Filter", selection: $filter) {
                ForEach(QuarantineFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Spacer()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cask, authority, team ID…", text: $searchFilter)
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
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 260)
        }
    }

    // MARK: - Auditing Progress Card

    private var auditingProgressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Auditing Installed Casks…")
                    .font(.subheadline.bold())
                Spacer()
                if let active = auditor.activeOperationItem {
                    Text(active)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: auditor.auditProgress, total: 1.0)
                .progressViewStyle(.linear)
        }
        .padding(Spacing.md)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Items List View

    private var itemsListView: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(filteredItems) { item in
                caskCardView(item: item)
            }
        }
    }

    private func caskCardView(item: CaskQuarantineItem) -> some View {
        let isExpanded = expandedItemIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                appIcon(for: item)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.caskName)
                            .font(.headline)

                        statusBadge(for: item.status)
                    }

                    HStack(spacing: 6) {
                        Text(item.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        if let teamID = item.teamIdentifier {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text("Team: \(teamID)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                        }

                        if let auth = item.signingAuthority {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(auth)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if item.isQuarantined {
                    Button {
                        Task {
                            let res = await auditor.removeQuarantine(for: item)
                            switch res {
                            case .success:
                                showToast("Cleared quarantine for \(item.caskName).")
                            case let .failure(error):
                                showToast("Could not clear quarantine for \(item.caskName): \(error.localizedDescription)")
                            }
                        }
                    } label: {
                        Label("Clear Quarantine", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.bundleURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal in Finder")

                Button {
                    withAnimation {
                        if isExpanded {
                            expandedItemIDs.remove(item.id)
                        } else {
                            expandedItemIDs.insert(item.id)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }

            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Bundle Location:")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(item.bundleURL.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if let details = item.quarantineDetails {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quarantine Metadata:")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                if let agent = details.agent {
                                    Label("Agent: \(agent)", systemImage: "network")
                                        .font(.caption2)
                                }
                                Label("Date: \(details.formattedDate)", systemImage: "clock")
                                    .font(.caption2)
                                if let uuid = details.uuid {
                                    Label("UUID: \(uuid.prefix(8))…", systemImage: "barcode")
                                        .font(.caption2.monospaced())
                                }
                            }
                            .foregroundStyle(.secondary)

                            Text(details.rawString)
                                .font(.system(size: 10, design: .monospaced))
                                .padding(6)
                                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                .textSelection(.enabled)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("No extended quarantine attributes found on this application bundle.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(Spacing.md)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(item.isQuarantined ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private func statusBadge(for status: QuarantineStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
            Text(status.rawValue)
        }
        .font(.caption2.bold())
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status.badgeColor.opacity(0.12), in: Capsule())
        .foregroundStyle(status.badgeColor)
    }

    private func appIcon(for item: CaskQuarantineItem) -> some View {
        Group {
            if let icon = NSWorkspace.shared.icon(forFile: item.bundleURL.path) as NSImage? {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Casks Match Filter",
            systemImage: "checkmark.shield",
            description: Text(searchFilter.isEmpty ?
                              "No casks found in the selected filter category." :
                              "No installed casks match '\(searchFilter)'.")
        )
        .padding(.vertical, 40)
    }

    // MARK: - Metric Card Component

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

    // MARK: - Action Helpers

    private func runAudit() {
        Task {
            _ = await auditor.auditAllInstalledCasks(casks: manager.packages)
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
