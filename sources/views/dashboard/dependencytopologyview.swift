import SwiftUI

struct DependencyTopologyView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject private var topologyManager = BrewStoreDependencyTopologyManager.shared
    @State private var selectedPackageForDetail: BrewStorePackage?
    @State private var searchQuery = ""
    @State private var showingExportSheet = false

    var showHeader: Bool = true

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: Spacing.xs) {
            if topologyManager.isAnalyzing {
                ProgressView().controlSize(.small)
            }

            Button {
                showingExportSheet = true
            } label: {
                Label("Export Graph", systemImage: "arrow.down.doc.fill")
            }
            .controlSize(.small)
            .accessibilityIdentifier("Topology.ExportButton")

            Button {
                topologyManager.analyzeTopology(manager: manager)
            } label: {
                Label("Re-Analyze", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(topologyManager.isAnalyzing || manager.isOperating)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header
                if showHeader {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Package Dependencies & Integrity").font(.title2.bold())
                            Text("System dependency map, shared libraries, unused packages, and binary links.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        actionButtons
                    }
                }

                // Error State
                if let error = topologyManager.errorMessage ?? (topologyManager.topology == nil && !topologyManager.isAnalyzing ? manager.errorMessage : nil) {
                    errorStateView(error: error)
                }
                // Loading State (Initial Analysis)
                else if topologyManager.isAnalyzing, topologyManager.topology == nil {
                    loadingStateView
                }
                // Populated / Content State
                else if let top = topologyManager.topology {
                    // Summary Stats Cards
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Spacing.xs)], spacing: Spacing.xs) {
                        statCard(title: "Dependencies", value: "\(top.totalDependenciesMapped)", icon: "point.3.connected.trianglepath.dotted", color: .blue)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                topologyManager.selectedTab = .foundations
                            }
                        } label: {
                            statCard(title: "Shared Libraries", value: "\(top.sharedFoundations.count)", icon: "pyramid.fill", color: .purple, isSelected: topologyManager.selectedTab == .foundations)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(topologyManager.selectedTab == .foundations ? .isSelected : [])
                        .accessibilityIdentifier("Topology.Card.Foundations")

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                topologyManager.selectedTab = .orphans
                            }
                        } label: {
                            statCard(title: "Unused Packages", value: "\(top.orphanLeaves.count)", icon: "leaf.fill", color: top.hasOrphans ? .orange : .green, isSelected: topologyManager.selectedTab == .orphans)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(topologyManager.selectedTab == .orphans ? .isSelected : [])
                        .accessibilityIdentifier("Topology.Card.Orphans")

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                topologyManager.selectedTab = .integrity
                            }
                        } label: {
                            statCard(title: "Broken Links", value: "\(top.linkageIssues.count)", icon: "exclamationmark.triangle.fill", color: top.linkageIssues.isEmpty ? .green : .red, isSelected: topologyManager.selectedTab == .integrity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(topologyManager.selectedTab == .integrity ? .isSelected : [])
                        .accessibilityIdentifier("Topology.Card.Integrity")
                    }

                    // Segmented Tab Switcher and In-Section Search Bar
                    HStack(spacing: Spacing.sm) {
                        Picker("Dependency View", selection: $topologyManager.selectedTab) {
                            ForEach(TopologyTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 440)
                        .accessibilityIdentifier("Topology.SegmentedPicker")

                        Spacer()

                        BrewStoreSectionSearchBar(text: $searchQuery, placeholder: "Search dependency packages…")
                            .frame(minWidth: 160, maxWidth: 240)

                        if !showHeader {
                            actionButtons
                        }
                    }

                    // Tab Content
                    Group {
                        switch topologyManager.selectedTab {
                        case .foundations:
                            foundationsList(foundations: filteredFoundations(top.sharedFoundations), totalCount: top.sharedFoundations.count)
                        case .orphans:
                            orphansList(orphans: filteredOrphans(top.orphanLeaves), totalOrphanCount: top.orphanLeaves.count)
                        case .integrity:
                            integrityList(issues: filteredIssues(top.linkageIssues), totalCount: top.linkageIssues.count)
                        }
                    }
                    .id(topologyManager.selectedTab)
                    .animation(nil, value: topologyManager.selectedTab)
                } else {
                    loadingStateView
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .detailModalOverlay(item: $selectedPackageForDetail) { pkg in
            PackageDetailView(manager: manager, package: pkg, onDismiss: {
                selectedPackageForDetail = nil
            })
        }
        .sheet(isPresented: $showingExportSheet) {
            DependencyExportSheet(manager: manager)
        }
        .task {
            topologyManager.ensureTopologyUpdated(manager: manager)
        }
        .onAppear {
            topologyManager.ensureTopologyUpdated(manager: manager)
        }
        .onChange(of: manager.packages) { _, _ in
            topologyManager.ensureTopologyUpdated(manager: manager)
        }
        .onChange(of: manager.isLoading) { _, loading in
            if !loading {
                topologyManager.ensureTopologyUpdated(manager: manager)
            }
        }
    }

    // MARK: - Loading & Error States

    private var loadingStateView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
            Text("Analyzing System Dependencies & Orphan Leaves…")
                .font(.headline)
            Text("Mapping reverse dependencies, shared library linkages, and orphaned packages across your Homebrew environment.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorStateView(error: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Topology Analysis Notice")
                    .font(.headline)
            }

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry Analysis") {
                topologyManager.analyzeTopology(manager: manager)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func filteredFoundations(_ list: [SharedFoundationLibrary]) -> [SharedFoundationLibrary] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.lowercased().contains(q) ||
                $0.id.lowercased().contains(q) ||
                $0.dependentPackageIDs.contains { $0.lowercased().contains(q) }
        }
    }

    private func filteredOrphans(_ list: [OrphanLeafPackage]) -> [OrphanLeafPackage] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.lowercased().contains(q) ||
                $0.id.lowercased().contains(q) ||
                $0.description.lowercased().contains(q)
        }
    }

    private func filteredIssues(_ list: [BrokenLinkageIssue]) -> [BrokenLinkageIssue] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.id.lowercased().contains(q) ||
                $0.binaryPath.lowercased().contains(q) ||
                $0.reason.lowercased().contains(q)
        }
    }

    // MARK: - Summary Card

    private func statCard(title: String, value: String, icon: String, color: Color, isSelected: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? color.opacity(0.8) : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    // MARK: - 1. Shared Foundations List

    private func foundationsList(foundations: [SharedFoundationLibrary], totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Shared Foundation Libraries (\(foundations.count))")
                .font(.headline)

            Text("These packages act as the bedrock for other tools on your Mac. Removing them directly would break multiple dependents.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if totalCount == 0 {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                    Text("No shared foundation dependencies detected on this Mac.").font(.subheadline)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            } else if foundations.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text("No foundation packages match \"\(searchQuery)\".").font(.subheadline)
                    Spacer()
                    Button("Clear Filter") { searchQuery = "" }
                        .controlSize(.small)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(foundations.prefix(50).enumerated()), id: \.element.id) { index, lib in
                        HStack(spacing: 14) {
                            Text("#\(index + 1)")
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(lib.name).font(.subheadline.bold())
                                    if lib.isInstalled {
                                        Text("Installed")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.green.opacity(0.12), in: Capsule())
                                    }
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        Text("Required by:").font(.caption2).foregroundStyle(.secondary)
                                        ForEach(lib.dependentPackageIDs, id: \.self) { dep in
                                            Text(dep)
                                                .font(.caption2.monospaced())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                                        }
                                    }
                                }
                            }

                            Spacer()

                            Text("\(lib.dependentCount) Dependents")
                                .font(.caption.bold())
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())

                            if let pkg = manager.packages.first(where: { $0.id.caseInsensitiveCompare(lib.id) == .orderedSame }) {
                                Button("Inspect") {
                                    selectedPackageForDetail = pkg
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    // MARK: - 2. Orphan Leaf Analyzer

    private func orphansList(orphans: [OrphanLeafPackage], totalOrphanCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaf Packages with Zero Dependents (\(orphans.count))")
                        .font(.headline)
                    Text("These packages have no other installed packages depending on them. If you installed a package intentionally as a primary tool, keep it. If it was installed as a dependency for software you removed, it can be safely uninstalled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !orphans.isEmpty {
                    Button(role: .destructive) {
                        let packages = orphans.compactMap { orphan in
                            manager.packages.first { $0.id.caseInsensitiveCompare(orphan.id) == .orderedSame && $0.isInstalled }
                        }
                        BrewStoreUninstallCoordinator.shared.requestAutoremove(packages: packages, manager: manager)
                    } label: {
                        Label("Clean All Leftover Orphans (brew autoremove)", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }
            }

            // Safety Notice
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("Zero dependents does not mean unused: Top-level command-line tools you installed directly are listed here because nothing else relies on them. Only remove packages you no longer use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            if totalOrphanCount == 0 {
                // Empty state: System is fully optimized
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Orphan Packages Found")
                            .font(.subheadline.bold())
                        Text("No orphan packages found in the most recent analysis.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            } else if orphans.isEmpty {
                // Empty search filter state
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Matching Orphan Packages")
                            .font(.subheadline.bold())
                        Text("No orphaned packages match your search filter \"\(searchQuery)\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear Search") {
                        searchQuery = ""
                    }
                    .controlSize(.small)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            } else {
                // Populated state
                LazyVStack(spacing: 8) {
                    ForEach(orphans) { orphan in
                        let pkg = manager.packages.first(where: { $0.id.caseInsensitiveCompare(orphan.id) == .orderedSame }) ?? BrewStorePackage(
                            id: orphan.id,
                            name: orphan.name,
                            description: orphan.description,
                            homepage: "",
                            version: "",
                            kind: orphan.kind,
                            isInstalled: true
                        )
                        HStack(spacing: 12) {
                            Image(systemName: "leaf.fill")
                                .foregroundStyle(.orange)
                                .font(.body)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(orphan.name).font(.subheadline.bold())
                                    Text("Leaf Package")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                    Text("0 Dependents")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if !orphan.description.isEmpty {
                                    Text(orphan.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()

                            Button("Inspect") {
                                selectedPackageForDetail = pkg
                            }
                            .controlSize(.small)
                            .accessibilityIdentifier("OrphanLeaves.Inspect.\(orphan.id)")

                            Button(role: .destructive) {
                                BrewStoreUninstallCoordinator.shared.requestUninstall(package: pkg, manager: manager)
                            } label: {
                                Label("Uninstall…", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(manager.isOperating)
                            .accessibilityIdentifier("OrphanLeaves.Delete.\(orphan.id)")
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("OrphanLeaves.Row.\(orphan.id)")
                    }
                }
                .accessibilityIdentifier("Topology.OrphanLeavesList")
            }
        }
    }

    // MARK: - 3. Linkage & Integrity

    private func integrityList(issues: [BrokenLinkageIssue], totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Binary Linkage Integrity (\(issues.count))")
                .font(.headline)

            Text("Scans installed dynamic binaries (Mach-O) for missing shared dylib dependencies or broken pointers.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if totalCount == 0 {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                    Text("All installed binaries have healthy, valid shared library linkages.").font(.subheadline)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            } else if issues.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text("No linkage issues match \"\(searchQuery)\".").font(.subheadline)
                    Spacer()
                    Button("Clear Filter") { searchQuery = "" }
                        .controlSize(.small)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(issues) { issue in
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.severity == "critical" ? .red : .orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.id).font(.subheadline.bold())
                                Text(issue.binaryPath)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(issue.reason)
                                    .font(.caption2)
                                    .foregroundStyle(issue.severity == "critical" ? .red : .primary)
                            }

                            Spacer()

                            Button("Reinstall (brew reinstall)") {
                                if let pkg = manager.packages.first(where: { $0.id.caseInsensitiveCompare(issue.id) == .orderedSame }) {
                                    manager.perform(package: pkg, action: .reinstall)
                                }
                            }
                            .controlSize(.small)
                            .disabled(manager.isOperating)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

struct DependencyExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    @State private var selectedExportFormat = 0 // 0: Mermaid, 1: Lockfile JSON, 2: Markdown Tree
    @State private var copiedToast = false

    private var exportContent: String {
        switch selectedExportFormat {
        case 0:
            BrewStoreLockfileGenerator.generateMermaidGraph(packages: manager.packages)
        case 1:
            BrewStoreLockfileGenerator.generateJSONString(packages: manager.packages, taps: manager.taps)
        case 2:
            BrewStoreLockfileGenerator.generateMarkdownTree(packages: manager.packages)
        default:
            ""
        }
    }

    private var exportFileExtension: String {
        switch selectedExportFormat {
        case 0: "mmd"
        case 1: "json"
        case 2: "md"
        default: "txt"
        }
    }

    private var exportFileName: String {
        switch selectedExportFormat {
        case 0: "Brewfile-dependency-graph.mmd"
        case 1: "Brewfile.lock.json"
        case 2: "Brewfile-dependency-tree.md"
        default: "export.txt"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Dependency Graph & Lockfile")
                        .font(.headline)
                    Text("Export visual architecture graphs, deterministic lockfiles, or hierarchy trees.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Format Switcher
            HStack(spacing: 12) {
                Picker("Export Format", selection: $selectedExportFormat) {
                    Text("Mermaid Graph (.mmd)").tag(0)
                    Text("Deterministic Lockfile (JSON)").tag(1)
                    Text("Markdown Hierarchy Tree (.md)").tag(2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)

                Spacer()

                if copiedToast {
                    Text("Copied to Clipboard!")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(exportContent, forType: .string)
                    withAnimation {
                        copiedToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            copiedToast = false
                        }
                    }
                } label: {
                    Label("Copy Code", systemImage: "doc.on.doc")
                }
                .controlSize(.small)

                Button {
                    saveExportFile()
                } label: {
                    Label("Save File…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Code Preview
            ScrollView {
                Text(exportContent)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 700, height: 540)
    }

    private func saveExportFile() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = exportFileName

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? exportContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
