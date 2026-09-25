import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum BrewfileStudioTab: String, CaseIterable, Identifiable {
    case drift = "System Drift"
    case projects = "Project Scanner"
    case editor = "Visual Studio"
    case cleanup = "Prune & Cleanup"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .drift: "arrow.triangle.pull"
        case .projects: "folder.badge.gearshape"
        case .editor: "pencil.and.list.clipboard"
        case .cleanup: "trash"
        }
    }
}

struct BrewfileManagerView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var bundleManager = BrewStoreBundleManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: BrewfileStudioTab = .drift
    @State private var searchFilter: String = ""
    @State private var showingFileImporter = false
    @State private var showingFileExporter = false
    @State private var showingDirectoryPicker = false
    @State private var showingCleanupConfirmation = false
    @State private var statusToast: String?

    // Visual Editor State
    @State private var editorContent: String = ""
    @State private var newEntryKind: DeclarativeEntryKind = .brew
    @State private var newEntryName: String = ""
    @State private var isDirty: Bool = false

    private var trackedURL: URL? {
        bundleManager.trackedBrewfileURL
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

            Divider()

            tabBarView
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)

            Divider()

            ZStack {
                switch selectedTab {
                case .drift:
                    driftContentView
                case .projects:
                    projectScannerView
                case .editor:
                    visualStudioView
                case .cleanup:
                    cleanupManagerView
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
        .frame(minWidth: 820, idealWidth: 900, minHeight: 600, idealHeight: 680)
        .onAppear {
            loadInitialDrift()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let file = urls.first {
                bundleManager.setTrackedBrewfile(url: file)
                refreshDrift()
                loadEditorContent()
                showToast("Tracked \(file.lastPathComponent).")
            }
        }
        .confirmationDialog(
            "Prune Unmanaged Packages?",
            isPresented: $showingCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Prune \(bundleManager.dryRunCleanupList.count) Packages (brew bundle cleanup --force)", role: .destructive) {
                if let url = trackedURL {
                    Task {
                        let res = await bundleManager.executeCleanup(for: url, zap: false, manager: manager)
                        showToast(res.message)
                        refreshDrift()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will uninstall all local packages that are not explicitly declared in '\(trackedURL?.lastPathComponent ?? "Brewfile")'. This operation cannot be undone.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Declarative Brewfile & Bundle Studio")
                        .font(.title2.bold())

                    if bundleManager.isCheckingDrift || bundleManager.isOperating {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let url = trackedURL {
                    HStack(spacing: 4) {
                        Text("Tracked:")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(url.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("No primary Brewfile tracked. Select or dump a Brewfile to start drift tracking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                showingFileImporter = true
            } label: {
                Label(trackedURL == nil ? "Select Brewfile" : "Change File", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                dumpSystemState()
            } label: {
                Label("Dump System", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(bundleManager.isOperating)

            if let url = trackedURL {
                Button {
                    Task {
                        let res = await bundleManager.installBundle(from: url, noLock: true, manager: manager)
                        showToast(res.message)
                        refreshDrift()
                    }
                } label: {
                    Label("Sync Bundle", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(bundleManager.isOperating)
            }

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
    }

    // MARK: - Tab Bar

    private var tabBarView: some View {
        HStack {
            Picker("Studio Mode", selection: $selectedTab) {
                ForEach(BrewfileStudioTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)

            Spacer()

            if let report = bundleManager.activeDriftReport {
                HStack(spacing: 6) {
                    Image(systemName: report.status.iconName)
                    Text(report.status.rawValue)
                }
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(report.status.badgeColor.opacity(0.12), in: Capsule())
                .foregroundStyle(report.status.badgeColor)
            }
        }
    }

    // MARK: - Tab 1: System Drift View

    private var driftContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                driftOverviewBanner

                if let report = bundleManager.activeDriftReport {
                    if report.isSatisfied {
                        satisfiedCard
                    }

                    if !report.missingFormulae.isEmpty || !report.missingCasks.isEmpty || !report.missingTaps.isEmpty {
                        missingSection(report: report)
                    }

                    if !report.unmanagedFormulae.isEmpty || !report.unmanagedCasks.isEmpty {
                        unmanagedSection(report: report)
                    }
                } else {
                    ContentUnavailableView(
                        "No Brewfile Selected",
                        systemImage: "doc.questionmark",
                        description: Text("Select a tracked Brewfile or click 'Dump System' to establish a baseline declarative environment.")
                    )
                    .padding(.vertical, 40)
                }
            }
            .padding(Spacing.lg)
        }
    }

    private var driftOverviewBanner: some View {
        HStack(spacing: Spacing.md) {
            metricCard(
                title: "Drift Status",
                value: bundleManager.activeDriftReport?.status.rawValue ?? "Untracked",
                icon: bundleManager.activeDriftReport?.status.iconName ?? "questionmark.circle",
                color: bundleManager.activeDriftReport?.status.badgeColor ?? .secondary
            )

            metricCard(
                title: "Missing in System",
                value: "\(bundleManager.activeDriftReport?.totalMissingCount ?? 0)",
                icon: "arrow.down.circle.fill",
                color: (bundleManager.activeDriftReport?.totalMissingCount ?? 0) > 0 ? .orange : .green
            )

            metricCard(
                title: "Unmanaged on Mac",
                value: "\(bundleManager.activeDriftReport?.totalUnmanagedCount ?? 0)",
                icon: "exclamationmark.triangle.fill",
                color: (bundleManager.activeDriftReport?.totalUnmanagedCount ?? 0) > 0 ? .yellow : .secondary
            )

            metricCard(
                title: "Last Audited",
                value: bundleManager.activeDriftReport != nil ? "Just now" : "—",
                icon: "clock.arrow.circlepath",
                color: .blue
            )
        }
    }

    private var satisfiedCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("System Perfectly Synchronized")
                    .font(.headline)
                Text("All packages declared in your tracked Brewfile are installed, and no unmanaged package drift was detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.2), lineWidth: 1))
    }

    private func missingSection(report: BrewfileDriftReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Missing from System (Declared in Brewfile)")
                    .font(.headline)
                Spacer()
                if let url = trackedURL {
                    Button {
                        Task {
                            let res = await bundleManager.installBundle(from: url, noLock: true, manager: manager)
                            showToast(res.message)
                            refreshDrift()
                        }
                    } label: {
                        Label("Install Missing (\(report.totalMissingCount))", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(bundleManager.isOperating)
                }
            }

            VStack(spacing: 6) {
                ForEach(report.missingTaps, id: \.self) { tap in
                    driftRow(name: tap, type: "Tap", icon: "point.3.connected.trianglepath.dotted", color: .purple)
                }
                ForEach(report.missingCasks, id: \.self) { cask in
                    driftRow(name: cask, type: "Cask", icon: "app.fill", color: .blue)
                }
                ForEach(report.missingFormulae, id: \.self) { formula in
                    driftRow(name: formula, type: "Formula", icon: "terminal.fill", color: .green)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func unmanagedSection(report: BrewfileDriftReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unmanaged Packages on Mac (Not in Brewfile)")
                        .font(.headline)
                    Text("These packages are installed locally but missing from your tracked declarative stack.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectedTab = .cleanup
                } label: {
                    Label("Inspect Cleanup", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 6) {
                ForEach(report.unmanagedCasks.prefix(10), id: \.self) { cask in
                    driftRow(name: cask, type: "Cask", icon: "app.fill", color: .blue)
                }
                ForEach(report.unmanagedFormulae.prefix(15), id: \.self) { formula in
                    driftRow(name: formula, type: "Formula", icon: "terminal.fill", color: .green)
                }
                if report.totalUnmanagedCount > 25 {
                    Text("+ \(report.totalUnmanagedCount - 25) additional unmanaged packages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func driftRow(name: String, type: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)

            Text(name)
                .font(.subheadline.bold())

            Spacer()

            Text(type)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Tab 2: Project Scanner View

    private var projectScannerView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Project & Git Worktree Brewfile Discovery")
                        .font(.title3.bold())
                    Text("Scan developer repositories and git worktrees to discover local project dependency manifests.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    pickDirectoryAndScan()
                } label: {
                    Label("Select Directory to Scan…", systemImage: "folder.badge.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)

            if bundleManager.scannedProjectBrewfiles.isEmpty {
                ContentUnavailableView(
                    "No Project Brewfiles Discovered",
                    systemImage: "folder.badge.gearshape",
                    description: Text("Click 'Select Directory to Scan' to discover Brewfile and .Brewfile manifests in your code projects.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(bundleManager.scannedProjectBrewfiles, id: \.self) { fileURL in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileURL.lastPathComponent)
                                .font(.headline)
                            Text(fileURL.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Track as Primary") {
                            bundleManager.setTrackedBrewfile(url: fileURL)
                            refreshDrift()
                            showToast("Now tracking \(fileURL.lastPathComponent).")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            Task {
                                let res = await bundleManager.installBundle(from: fileURL, noLock: true, manager: manager)
                                showToast(res.message)
                            }
                        } label: {
                            Label("Install Stack", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(bundleManager.isOperating)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Tab 3: Visual Studio View

    private var visualStudioView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Visual Brewfile Editor")
                    .font(.headline)

                Spacer()

                Button("Reload from File") {
                    loadEditorContent()
                    isDirty = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save Brewfile") {
                    saveEditorContent()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isDirty || trackedURL == nil)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)

            // Add new entry toolbar
            HStack(spacing: 8) {
                Picker("Type", selection: $newEntryKind) {
                    ForEach(DeclarativeEntryKind.allCases, id: \.self) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .frame(width: 140)

                TextField("Package Name (e.g. gcc, ghostty, user/tap)", text: $newEntryName)
                    .textFieldStyle(.roundedBorder)

                Button("Add Entry") {
                    addEntryToContent()
                }
                .buttonStyle(.bordered)
                .disabled(newEntryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Spacing.lg)

            // Raw Text Editor Canvas
            TextEditor(text: $editorContent)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.md)
                .onChange(of: editorContent) { _, _ in
                    isDirty = true
                }
        }
    }

    // MARK: - Tab 4: Prune & Cleanup View

    private var cleanupManagerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Declarative Pruning & Cleanup (`brew bundle cleanup`)")
                            .font(.title3.bold())
                        Text("Remove packages that have drifted from your declared configuration to maintain an immaculate system state.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        runDryRunCleanup()
                    } label: {
                        Label("Preview Cleanup (Dry Run)", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(bundleManager.isOperating || trackedURL == nil)

                    if !bundleManager.dryRunCleanupList.isEmpty {
                        Button("Prune All Unmanaged", role: .destructive) {
                            showingCleanupConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(bundleManager.isOperating)
                    }
                }

                if bundleManager.dryRunCleanupList.isEmpty {
                    ContentUnavailableView(
                        "No Cleanup Pending",
                        systemImage: "sparkles",
                        description: Text("Click 'Preview Cleanup' to run an official Homebrew dry-run audit of packages eligible for uninstallation.")
                    )
                    .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Eligible for Pruning (\(bundleManager.dryRunCleanupList.count))")
                            .font(.headline)

                        ForEach(bundleManager.dryRunCleanupList, id: \.self) { item in
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                Text(item)
                                    .font(.subheadline.monospaced())
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(Spacing.lg)
        }
    }

    // MARK: - Helpers & Subviews

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

    private func loadInitialDrift() {
        if let url = trackedURL {
            Task {
                _ = await bundleManager.checkDrift(for: url, packages: manager.packages, taps: manager.taps)
                loadEditorContent()
            }
        }
    }

    private func refreshDrift() {
        if let url = trackedURL {
            Task {
                _ = await bundleManager.checkDrift(for: url, packages: manager.packages, taps: manager.taps)
            }
        }
    }

    private func loadEditorContent() {
        guard let url = trackedURL, let content = try? String(contentsOf: url, encoding: .utf8) else {
            editorContent = ""
            return
        }
        editorContent = content
        isDirty = false
    }

    private func saveEditorContent() {
        guard let url = trackedURL else { return }
        do {
            try editorContent.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            refreshDrift()
            showToast("Saved \(url.lastPathComponent).")
        } catch {
            showToast("Failed to save: \(error.localizedDescription)")
        }
    }

    private func addEntryToContent() {
        let name = newEntryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let snippet: String
        switch newEntryKind {
        case .tap: snippet = "tap \"\(name)\""
        case .brew: snippet = "brew \"\(name)\""
        case .cask: snippet = "cask \"\(name)\""
        case .mas: snippet = "mas \"\(name)\", id: 0"
        case .vscode: snippet = "vscode \"\(name)\""
        }
        editorContent += "\n\(snippet)"
        newEntryName = ""
        isDirty = true
    }

    private func dumpSystemState() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let target = home.appendingPathComponent(".Brewfile")
        Task {
            let res = await bundleManager.dumpSystemBrewfile(to: target, includeComments: true, manager: manager)
            showToast(res.message)
            refreshDrift()
            loadEditorContent()
        }
    }

    private func runDryRunCleanup() {
        guard let url = trackedURL else { return }
        Task {
            let res = await bundleManager.dryRunCleanup(for: url)
            showToast(res.message)
        }
    }

    private func pickDirectoryAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan Directory"
        if panel.runModal() == .OK, let selectedURL = panel.url {
            Task {
                let found = await bundleManager.scanDirectory(at: selectedURL)
                showToast("Found \(found.count) Brewfile\(found.count == 1 ? "" : "s").")
            }
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
