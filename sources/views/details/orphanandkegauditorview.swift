import AppKit
import SwiftUI

enum AuditorTab: String, CaseIterable, Identifiable {
    case orphans = "Orphan Dependencies"
    case explicitLeaves = "Explicit Leaves"
    case kegOnly = "Keg-Only Packages"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .orphans: return "leaf.arrow.triangle.circlepath"
        case .explicitLeaves: return "shippingbox.fill"
        case .kegOnly: return "link.badge.plus"
        }
    }
}

struct OrphanAndKegAuditorView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var auditor = OrphanAndKegAuditor.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: AuditorTab = .orphans
    @State private var searchFilter: String = ""
    @State private var showingAutoremoveConfirm = false
    @State private var orphanToPrune: LeafPackageItem?
    @State private var kegToToggle: (item: KegOnlyPackageItem, forceLink: Bool)?
    @State private var copiedPackageID: String?
    @State private var statusToast: String?

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

            tabBarView
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)

            Divider()

            ZStack {
                if auditor.isAuditing && auditor.report == nil {
                    loadingView
                } else if let report = auditor.report {
                    contentCanvas(report: report)
                } else {
                    emptyInitialView
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
        .frame(minWidth: 720, idealWidth: 800, minHeight: 520, idealHeight: 600)
        .onAppear {
            if auditor.report == nil {
                auditor.auditEnvironment(prefix: effectivePrefix, manager: manager)
            }
        }
        .confirmationDialog(
            "Prune All Orphan Dependencies?",
            isPresented: $showingAutoremoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Prune All (brew autoremove)", role: .destructive) {
                Task {
                    let result = await auditor.pruneAllOrphans(prefix: effectivePrefix, manager: manager)
                    showToast(result.message)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homebrew will automatically uninstall all orphan packages that were installed as dependencies but are no longer required by any formula.")
        }
        .confirmationDialog(
            "Prune \(orphanToPrune?.name ?? "Package")?",
            isPresented: Binding(
                get: { orphanToPrune != nil },
                set: { if !$0 { orphanToPrune = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Prune (\(orphanToPrune?.formattedSize ?? "0 B"))", role: .destructive) {
                if let pkg = orphanToPrune {
                    Task {
                        let success = await auditor.pruneSingleOrphan(packageID: pkg.id, prefix: effectivePrefix, manager: manager)
                        showToast(success ? "Pruned \(pkg.name)." : "Failed to prune \(pkg.name).")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will run 'brew uninstall \(orphanToPrune?.id ?? "")' to reclaim \(orphanToPrune?.formattedSize ?? "") from your Cellar.")
        }
        .confirmationDialog(
            kegToToggle?.forceLink == true ? "Force Link \(kegToToggle?.item.name ?? "")?" : "Unlink \(kegToToggle?.item.name ?? "")?",
            isPresented: Binding(
                get: { kegToToggle != nil },
                set: { if !$0 { kegToToggle = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(kegToToggle?.forceLink == true ? "Force Link (brew link --overwrite --force)" : "Unlink (brew unlink)", role: kegToToggle?.forceLink == true ? .destructive : .none) {
                if let toggle = kegToToggle {
                    Task {
                        let res = await auditor.toggleKegLink(packageID: toggle.item.id, forceLink: toggle.forceLink, prefix: effectivePrefix, manager: manager)
                        showToast(res.message)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if kegToToggle?.forceLink == true {
                Text("Warning: Force linking a keg-only package symlinks its binaries directly into \(effectivePrefix)/bin, which may override macOS system binaries or other tools.")
            } else {
                Text("This will remove symlinks from \(effectivePrefix)/bin, restoring safe isolated status.")
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "leaf.arrow.triangle.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Leaves & Keg-Only Link Auditor")
                        .font(.title2.bold())

                    if auditor.isAuditing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text("Identify unneeded orphan dependencies to reclaim disk space, and manage keg-only shell PATH and compiler exports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                auditor.auditEnvironment(prefix: effectivePrefix, manager: manager)
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

    // MARK: - Tab Bar

    private var tabBarView: some View {
        HStack(spacing: 12) {
            Picker("Auditor Category", selection: $selectedTab) {
                ForEach(AuditorTab.allCases) { tab in
                    HStack(spacing: 4) {
                        Text(tab.rawValue)
                        if let report = auditor.report {
                            switch tab {
                            case .orphans:
                                Text("(\(report.orphans.count))")
                            case .explicitLeaves:
                                Text("(\(report.explicitLeaves.count))")
                            case .kegOnly:
                                Text("(\(report.kegOnlyPackages.count))")
                            }
                        }
                    }
                    .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter packages…", text: $searchFilter)
                    .textFieldStyle(.plain)
                    .frame(width: 160)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Content Canvas

    @ViewBuilder
    private func contentCanvas(report: OrphanAndKegAuditReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                switch selectedTab {
                case .orphans:
                    orphansTabContent(report: report)
                case .explicitLeaves:
                    explicitLeavesTabContent(report: report)
                case .kegOnly:
                    kegOnlyTabContent(report: report)
                }
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: - Tab 1: Orphans

    @ViewBuilder
    private func orphansTabContent(report: OrphanAndKegAuditReport) -> some View {
        let filtered = report.orphans.filter {
            searchFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(searchFilter)
        }

        if report.orphans.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Zero Orphan Dependencies")
                    .font(.headline)
                Text("All installed formulae in your Cellar are either explicitly requested packages or active dependencies of other software.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .frame(maxWidth: .infinity, minHeight: 250)
        } else {
            // Reclaim Banner
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Reclaim up to \(report.formattedTotalOrphanSpace)")
                        .font(.headline.bold())
                    Text("\(report.orphans.count) formulae were installed as dependencies but are no longer required by any installed package.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showingAutoremoveConfirm = true
                } label: {
                    Label("Prune All Orphans (brew autoremove)", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(auditor.operatingPackageID != nil)
            }
            .padding(Spacing.md)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.panel))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.panel)
                    .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
            )

            // Orphan Cards List
            LazyVStack(spacing: Spacing.xs) {
                ForEach(filtered) { orphan in
                    orphanRow(orphan: orphan)
                }
            }
        }
    }

    private func orphanRow(orphan: LeafPackageItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(orphan.name)
                        .font(.subheadline.bold())
                    Text("v\(orphan.version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(orphan.formattedSize)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                if !orphan.dependencies.isEmpty {
                    Text("Dependencies: \(orphan.dependencies.prefix(4).joined(separator: ", "))\(orphan.dependencies.count > 4 ? " +\(orphan.dependencies.count - 4) more" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(orphan.cellarPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Button {
                orphanToPrune = orphan
            } label: {
                Label("Prune", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(auditor.operatingPackageID != nil)
        }
        .padding(Spacing.sm)
        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: Radius.panel))
    }

    // MARK: - Tab 2: Explicit Leaves

    @ViewBuilder
    private func explicitLeavesTabContent(report: OrphanAndKegAuditReport) -> some View {
        let filtered = report.explicitLeaves.filter {
            searchFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(searchFilter)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Packages Explicitly Installed on Request")
                .font(.headline)
            Text("These are top-level formulae you explicitly ran 'brew install' for. They serve as root applications or toolchains.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)

        LazyVStack(spacing: Spacing.xs) {
            ForEach(filtered) { leaf in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(leaf.name)
                                .font(.subheadline.bold())
                            Text("v\(leaf.version)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(leaf.formattedSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !leaf.dependencies.isEmpty {
                            Text("Requires: \(leaf.dependencies.prefix(5).joined(separator: ", "))\(leaf.dependencies.count > 5 ? "…" : "")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: Radius.panel))
            }
        }
    }

    // MARK: - Tab 3: Keg-Only Packages

    @ViewBuilder
    private func kegOnlyTabContent(report: OrphanAndKegAuditReport) -> some View {
        let filtered = report.kegOnlyPackages.filter {
            searchFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(searchFilter)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Keg-Only Formulae & PATH Isolation")
                .font(.headline)
            Text("Keg-only packages are installed in Homebrew's opt directory, but not symlinked into global PATH to prevent conflicts with macOS system binaries or other toolchains.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)

        if filtered.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No matching keg-only packages found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(filtered) { keg in
                    kegOnlyCard(keg: keg)
                }
            }
        }
    }

    private func kegOnlyCard(keg: KegOnlyPackageItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(keg.name)
                            .font(.headline)
                        Text("v\(keg.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if keg.isForceLinked {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Force-Linked")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.shield.fill")
                                Text("Isolated (Recommended)")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1), in: Capsule())
                        }
                    }

                    Text(keg.humanReadableReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Link / Unlink Toggle
                Button {
                    kegToToggle = (keg, !keg.isForceLinked)
                } label: {
                    if keg.isForceLinked {
                        Label("Unlink", systemImage: "link.badge.plus")
                    } else {
                        Label("Force Link", systemImage: "link")
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(auditor.operatingPackageID != nil)
            }

            // Shell Environment Code Snippet
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Shell Exports")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        auditor.copyToClipboard(keg.fullShellSnippet)
                        copiedPackageID = keg.id
                        showToast("Copied shell exports for \(keg.name)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if copiedPackageID == keg.id {
                                copiedPackageID = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedPackageID == keg.id ? "checkmark" : "doc.on.doc")
                            Text(copiedPackageID == keg.id ? "Copied" : "Copy Exports")
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                }

                Text(keg.fullShellSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }
        }
        .padding(Spacing.md)
        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: Radius.panel))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - States & Helpers

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Auditing leaves and keg-only link matrix…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyInitialView: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Ready to Audit Environment")
                .font(.headline)
            Button("Run Audit") {
                auditor.auditEnvironment(prefix: effectivePrefix, manager: manager)
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
