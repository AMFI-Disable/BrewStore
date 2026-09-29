import AppKit
import SwiftUI

enum SourceStudioTab: String, CaseIterable, Identifiable {
    case toolchain = "Toolchain Matrix"
    case configurator = "Build Configurator"
    case logs = "Build Logs & Errors"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .toolchain: "cpu"
        case .configurator: "hammer"
        case .logs: "doc.text.magnifyingglass"
        }
    }
}

struct SourceBuildStudioView: View {
    @ObservedObject var manager: HomebrewManager
    var targetPackage: BrewStorePackage?
    @ObservedObject private var buildManager = BrewStoreSourceBuildManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: SourceStudioTab = .toolchain
    @State private var buildConfig = SourceBuildConfig()
    @State private var selectedFormulaPackage: BrewStorePackage?
    @State private var selectedHistoryItem: FormulaBuildHistoryItem?
    @State private var selectedLogFile: BuildLogFile?
    @State private var statusToast: String?
    @State private var showingBuildConfirmation = false

    private var activePackage: BrewStorePackage? {
        selectedFormulaPackage ?? targetPackage
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

            Divider()

            tabPickerView
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    switch selectedTab {
                    case .toolchain:
                        toolchainMatrixView
                    case .configurator:
                        buildConfiguratorView
                    case .logs:
                        buildLogsView
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
        .frame(minWidth: 840, idealWidth: 920, minHeight: 600, idealHeight: 680)
        .onAppear {
            if let target = targetPackage {
                selectedFormulaPackage = target
                selectedTab = .configurator
            }
            if buildManager.toolchainInfo == nil {
                Task {
                    _ = await buildManager.detectToolchain()
                    _ = await buildManager.scanAllBuildLogs()
                }
            }
        }
        .confirmationDialog(
            "Execute Source Compilation?",
            isPresented: $showingBuildConfirmation,
            titleVisibility: .visible
        ) {
            if let pkg = activePackage {
                Button("Build \(pkg.name) from Source", role: .destructive) {
                    triggerSourceBuild(for: pkg)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will compile '\(activePackage?.name ?? "the formula")' locally using your detected compiler. Depending on the size of the project, compilation may take several minutes.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "hammer.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.indigo)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Source Compiler & Build Studio")
                        .font(.title2.bold())

                    if buildManager.isDetectingToolchain || buildManager.isExecutingBuild {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("Local C/C++ compiler matrix, source build flags (`--build-from-source`, `--HEAD`), and build log diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    _ = await buildManager.detectToolchain()
                    _ = await buildManager.scanAllBuildLogs()
                    showToast("Refreshed compiler toolchain & build logs.")
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(buildManager.isDetectingToolchain || buildManager.isExecutingBuild)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
    }

    // MARK: - Tab Picker

    private var tabPickerView: some View {
        HStack {
            Picker("Mode", selection: $selectedTab) {
                ForEach(SourceStudioTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)

            Spacer()

            if let info = buildManager.toolchainInfo {
                HStack(spacing: 6) {
                    Circle()
                        .fill(info.isReadyForCompilation ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(info.isReadyForCompilation ? "Toolchain Ready" : "CLT Missing")
                        .font(.caption2.bold())
                        .foregroundStyle(info.isReadyForCompilation ? .green : .orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08), in: Capsule())
            }
        }
    }

    // MARK: - Tab 1: Toolchain Matrix View

    private var toolchainMatrixView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            cltCard

            clangCard

            buildSystemsGrid

            gccCard
        }
    }

    private var cltCard: some View {
        let info = buildManager.toolchainInfo
        let hasCLT = info?.hasCommandLineTools ?? false

        return HStack(spacing: 16) {
            Image(systemName: hasCLT ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(hasCLT ? .green : .orange)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Xcode Command Line Tools")
                        .font(.headline)
                    Text(hasCLT ? "Installed" : "Not Found")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(hasCLT ? Color.green.opacity(0.12) : Color.orange.opacity(0.12), in: Capsule())
                        .foregroundStyle(hasCLT ? .green : .orange)
                }

                if let path = info?.commandLineToolsPath {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Command Line Tools (xcode-select) are required for building Homebrew formulae from source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !hasCLT {
                Button {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
                    process.arguments = ["--install"]
                    try? process.run()
                    showToast("Launched Apple Command Line Tools installer.")
                } label: {
                    Label("Install Tools", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(Spacing.md)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var clangCard: some View {
        let info = buildManager.toolchainInfo

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Apple Clang C/C++ Compiler", systemImage: "apple.logo")
                    .font(.headline)
                Spacer()
                if let target = info?.clangTarget {
                    Text("Target: \(target)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info?.clangVersion ?? "Clang not detected")
                        .font(.title3.bold().monospaced())
                    Text("Default system C/C++ compiler used by Homebrew for formula builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var buildSystemsGrid: some View {
        let info = buildManager.toolchainInfo

        return HStack(spacing: Spacing.md) {
            buildSystemCard(name: "CMake", version: info?.cmakeVersion, icon: "shippingbox.fill")
            buildSystemCard(name: "GNU Make", version: info?.makeVersion, icon: "gearshape.2.fill")
            buildSystemCard(name: "Ninja", version: info?.ninjaVersion, icon: "bolt.fill")
        }
    }

    private func buildSystemCard(name: String, version: String?, icon: String) -> some View {
        let isPresent = version != nil

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(isPresent ? .blue : .secondary)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.bold())
                if let ver = version {
                    Text(ver)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Not Installed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var gccCard: some View {
        let info = buildManager.toolchainInfo
        let gccs = info?.availableGCCs ?? []

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("GNU Compiler Collection (GCC)", systemImage: "cpu")
                    .font(.headline)
                Spacer()
                Text("\(gccs.count) Available")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            if gccs.isEmpty {
                HStack {
                    Text("No Homebrew GCC compilers detected. Homebrew will compile using Apple Clang.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        manager.runCustomBrewCommand("brew install gcc")
                        showToast("Triggered 'brew install gcc' in background.")
                    } label: {
                        Label("Install GCC via Homebrew", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(gccs, id: \.self) { gcc in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(gcc)
                                .font(.caption.monospaced())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Tab 2: Build Configurator View

    private var buildConfiguratorView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            formulaSelectorSection

            optionsTogglesSection

            compilerSelectorSection

            commandPreviewSection

            actionButtonsSection
        }
    }

    private var formulaSelectorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Target Formula")
                .font(.headline)

            if let pkg = activePackage {
                HStack(spacing: 12) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(pkg.name)
                                .font(.title3.bold())
                            Text("v\(pkg.version)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if pkg.isInstalled {
                                Text("Installed")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text(pkg.description.isEmpty ? pkg.id : pkg.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(Spacing.md)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ContentUnavailableView(
                    "No Formula Selected",
                    systemImage: "terminal",
                    description: Text("Select a formula from your installed or discovery catalog to configure custom compilation flags.")
                )
                .frame(maxWidth: .infinity, maxHeight: 120)
            }
        }
    }

    private var optionsTogglesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source Compilation Flags")
                .font(.headline)

            VStack(spacing: 8) {
                Toggle(isOn: $buildConfig.buildFromSource) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build from Source (`--build-from-source`)")
                            .font(.subheadline.bold())
                        Text("Compiles source code locally instead of downloading pre-built bottles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle(isOn: $buildConfig.head) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build from Git HEAD (`--HEAD`)")
                            .font(.subheadline.bold())
                        Text("Clones the latest commit from the upstream repository's master or main branch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if buildConfig.head {
                    Divider()
                    Toggle(isOn: $buildConfig.fetchHead) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fetch Latest HEAD (`--fetch-HEAD`)")
                                .font(.subheadline.bold())
                            Text("Forces a git pull to fetch newest commits even if a previous HEAD clone exists.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                Toggle(isOn: $buildConfig.verbose) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verbose Compiler Output (`--verbose`)")
                            .font(.subheadline.bold())
                        Text("Prints every clang/gcc invocation and compilation warning in real-time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Spacing.md)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var compilerSelectorSection: some View {
        let gccs = buildManager.toolchainInfo?.availableGCCs ?? []

        return VStack(alignment: .leading, spacing: 6) {
            Text("C/C++ Compiler Override (`--cc`)")
                .font(.headline)

            Picker("Compiler", selection: $buildConfig.selectedCompiler) {
                Text("Default (Apple Clang)").tag(String?.none)
                Text("Force Clang (--cc=clang)").tag(String?.some("clang"))
                ForEach(gccs, id: \.self) { gcc in
                    Text("GCC: \(gcc) (--cc=\(gcc))").tag(String?.some(gcc))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)
        }
    }

    private var commandPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Generated Homebrew Command")
                .font(.headline)

            let cmd: String = {
                if let pkg = activePackage {
                    let args = buildConfig.generateArguments(for: pkg)
                    return "brew \(args.joined(separator: " "))"
                } else {
                    return buildConfig.commandPreview
                }
            }()

            HStack {
                Text(cmd)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                    showToast("Copied command to clipboard.")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard")
            }
            .padding(10)
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actionButtonsSection: some View {
        HStack {
            Spacer()

            if activePackage != nil {
                Button {
                    showingBuildConfirmation = true
                } label: {
                    Label("Execute Source Compilation", systemImage: "hammer.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(buildManager.isExecutingBuild || manager.isOperating)
            }
        }
    }

    // MARK: - Tab 3: Build Logs & Errors View

    private var buildLogsView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homebrew Build Logs Directory")
                        .font(.title3.bold())
                    Text("Inspecting ~/Library/Logs/Homebrew for failed compiler invocations, configure logs, and stack traces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !buildManager.buildHistory.isEmpty {
                    Button("Clear All Logs", role: .destructive) {
                        let cleared = buildManager.clearAllBuildLogs()
                        showToast("Cleared logs for \(cleared) packages.")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if buildManager.buildHistory.isEmpty {
                ContentUnavailableView(
                    "No Build Logs Found",
                    systemImage: "doc.plaintext",
                    description: Text("Homebrew logs source builds in '~/Library/Logs/Homebrew'. No previous source compilation logs were discovered.")
                )
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    // Left column: Formulae list
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Formulae with Build Logs")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(buildManager.buildHistory) { item in
                                    Button {
                                        selectedHistoryItem = item
                                        selectedLogFile = item.logFiles.first
                                    } label: {
                                        HStack {
                                            Image(systemName: item.hasErrors ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                                .foregroundStyle(item.hasErrors ? .red : .green)
                                            Text(item.formulaName)
                                                .font(.subheadline.bold())
                                            Spacer()
                                            Text("\(item.logFiles.count) files")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(8)
                                        .background(selectedHistoryItem?.id == item.id ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(width: 220, height: 350)
                        .padding(4)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Right column: Selected item logs
                    if let item = selectedHistoryItem {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.formulaName)
                                    .font(.headline)
                                Spacer()
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting(item.logFiles.map(\.url))
                                } label: {
                                    Label("Reveal in Finder", systemImage: "folder")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            // Log files pills
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(item.logFiles) { log in
                                        Button {
                                            selectedLogFile = log
                                        } label: {
                                            HStack(spacing: 4) {
                                                if log.hasErrors {
                                                    Image(systemName: "exclamationmark.circle.fill")
                                                        .foregroundStyle(.red)
                                                }
                                                Text(log.name)
                                                    .font(.caption.monospaced())
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(selectedLogFile?.id == log.id ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Selected log viewer
                            if let log = selectedLogFile {
                                VStack(alignment: .leading, spacing: 6) {
                                    if log.hasErrors {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                                                Text("Compiler Errors Detected (\(log.errorLines.count))").font(.caption.bold()).foregroundStyle(.red)
                                            }
                                            ForEach(log.errorLines.prefix(5), id: \.self) { line in
                                                Text(line)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                        .padding(8)
                                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    }

                                    ScrollView {
                                        Text(log.contentPreview.isEmpty ? "(Empty log file)" : log.contentPreview)
                                            .font(.system(size: 11, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    .frame(height: 220)
                                    .padding(8)
                                    .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Select a Formula",
                            systemImage: "doc.text",
                            description: Text("Select a formula from the list to view its compilation log files.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: 350)
                    }
                }
            }
        }
    }

    // MARK: - Action Helpers

    private func triggerSourceBuild(for package: BrewStorePackage) {
        Task {
            let success = await buildManager.executeSourceBuild(
                package: package,
                config: buildConfig,
                manager: manager
            )
            if success {
                showToast("Source build succeeded for \(package.name).")
            } else {
                showToast("Source build failed for \(package.name). Inspecting logs…")
                selectedTab = .logs
                selectedHistoryItem = buildManager.buildHistory.first { $0.formulaName == package.name }
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
