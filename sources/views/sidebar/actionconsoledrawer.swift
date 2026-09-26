import AppKit
import SwiftUI

struct ActionConsoleDrawer: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var preferences = BrewStorePreferences.shared

    @State private var filterText = ""
    @State private var autoScroll = true
    @State private var copiedLog = false
    @State private var customCommand = ""
    @State private var showingClearLocksConfirmation = false
    @State private var selectedLogLevel: LogFilterLevel = .all
    @AppStorage("BrewStore.consoleExpanded") private var isExpanded = false

    enum LogFilterLevel: String, CaseIterable, Identifiable {
        case all = "All"
        case build = "Build"
        case warnings = "Warn"
        case errors = "Errors"

        var id: String { rawValue }
    }

    private var filteredLogLines: [String] {
        let lines = manager.outputLog.components(separatedBy: .newlines)
        let levelFiltered: [String]
        switch selectedLogLevel {
        case .all:
            levelFiltered = lines
        case .build:
            levelFiltered = lines.filter { line in
                let l = line.lowercased()
                return l.contains("==>") || l.contains("building") || l.contains("compiling") || l.contains("make") || l.contains("clang") || l.contains("cmake") || l.contains("curl")
            }
        case .warnings:
            levelFiltered = lines.filter { line in
                let l = line.lowercased()
                return l.contains("warning:") || l.contains("warn:")
            }
        case .errors:
            levelFiltered = lines.filter { line in
                let l = line.lowercased()
                return l.contains("error:") || l.contains("failed") || l.contains("fatal:")
            }
        }

        if filterText.isEmpty {
            return levelFiltered
        }
        return levelFiltered.filter { $0.localizedCaseInsensitiveContains(filterText) }
    }

    private var currentDownloadProgress: Double? {
        guard manager.isOperating else { return nil }
        let recentLines = manager.outputLog.components(separatedBy: .newlines).suffix(5)
        for line in recentLines.reversed() {
            if let p = ANSIColorSerializer.extractDownloadProgress(from: line) {
                return p
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar of Console Drawer
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Text("Action Console")
                        .font(.caption.bold())

                    if manager.isOperating {
                        ProgressView().controlSize(.mini).padding(.leading, 2)
                        if let progress = currentDownloadProgress {
                            ProgressView(value: progress, total: 100.0)
                                .progressViewStyle(.linear)
                                .frame(width: 50)
                            Text("\(Int(progress))%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text(manager.activeOperationTitle ?? "Executing…")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 150, alignment: .leading)

                        Button("Cancel", role: .destructive) {
                            manager.cancelCurrentOperation()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.mini)
                        .help("Cancel running operation")
                    } else {
                        Text("Ready")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    // Quick Diagnostics (grouped in a Menu to prevent toolbar overflow)
                    if !manager.isOperating {
                        Menu {
                            Button("brew doctor") { runDiagnostic("doctor") }
                            Button("brew config") { runDiagnostic("config") }
                            Button("brew missing") { runDiagnostic("missing") }
                            Button("brew cleanup -n") { manager.runCustomBrewCommand("cleanup -n") }
                            Divider()
                            Button("Clear Homebrew Locks…") { showingClearLocksConfirmation = true }
                        } label: {
                            Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                                .font(.caption2)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Divider().frame(height: 14)
                    }

                    // Log Level Filter
                    Picker("", selection: $selectedLogLevel) {
                        ForEach(LogFilterLevel.allCases) { lvl in
                            Text(lvl.rawValue).tag(lvl)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .fixedSize()

                    // Search Filter
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
                        TextField("Filter…", text: $filterText)
                            .textFieldStyle(.plain)
                            .font(.caption2)
                            .frame(width: 75)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                    // Auto Scroll Toggle
                    Toggle(isOn: $autoScroll) {
                        Text("Auto-scroll").font(.caption2)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)

                    // Copy
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(manager.outputLog, forType: .string)
                        copiedLog = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copiedLog = false
                        }
                    } label: {
                        Image(systemName: copiedLog ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Console Output")

                    // Clear
                    Button {
                        manager.clearOutputLog()
                    } label: {
                        Image(systemName: "trash").font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Output Log")

                    // Resize Toggle
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Compact Console (210pt)" : "Expand Console (380pt)")

                    // Close Drawer Button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            preferences.showConsoleDrawer = false
                        }
                    } label: {
                        Image(systemName: "chevron.down").font(.caption2.bold())
                    }
                    .buttonStyle(.borderless)
                    .help("Hide Action Console (⌥~)")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Humanized Troubleshooting Hint Bar
            if let error = manager.errorMessage {
                let info = BrewStoreHumanizedErrorResolver.resolve(rawError: error)
                HStack(spacing: 8) {
                    Image(systemName: info.iconName)
                        .foregroundStyle(.orange)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(info.suggestion)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if info.category == .lock {
                        Button("Clear Locks") {
                            showingClearLocksConfirmation = true
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                    } else if info.category == .developerTools {
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("xcode-select --install", forType: .string)
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                    }

                    Button {
                        manager.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss suggestion")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.08))

                Divider()
            }

            if manager.isOperating || !manager.outputLog.isEmpty {
                LiveExecutionHUDView(manager: manager)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                Divider()
            }

            // Terminal Output Area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if manager.outputLog.isEmpty {
                            Text("No command output logged yet. Run any Homebrew operation or enter a command below to stream logs.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(12)
                        } else {
                            ForEach(Array(filteredLogLines.enumerated()), id: \.offset) { index, line in
                                Text(ANSIColorSerializer.attributedString(from: line, defaultColor: colorForLogLine(line)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.95))
                .onChange(of: manager.outputLog) {
                    if autoScroll, !filteredLogLines.isEmpty {
                        proxy.scrollTo(filteredLogLines.count - 1, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Interactive CLI Prompt Entry Bar
            HStack(spacing: 8) {
                Text("brew")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)

                TextField("command (e.g. info ripgrep, cat ffmpeg, deps --tree python)…", text: $customCommand)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit {
                        submitCustomCommand()
                    }

                if !customCommand.isEmpty {
                    Button(action: { customCommand = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Run") {
                    submitCustomCommand()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isOperating)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(height: isExpanded ? 380 : 210)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.secondary.opacity(0.2)),
            alignment: .top
        )
        .confirmationDialog(
            "Clear Homebrew Locks?",
            isPresented: $showingClearLocksConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Locks", role: .destructive) {
                manager.clearLocks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Active or stale lock files prevent installations and daemon operations. Make sure no Terminal brew commands are currently running.")
        }
    }

    private func submitCustomCommand() {
        let cmd = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        manager.runCustomBrewCommand(cmd)
    }

    private func colorForLogLine(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error:") || lower.contains("fatal:") || lower.contains("failed") {
            return .red
        }
        if lower.contains("warning:") || lower.contains("caveats") {
            return .orange
        }
        if lower.contains("==>") || lower.contains("successfully") || lower.contains("installed") {
            return .green
        }
        if lower.contains("downloading") || lower.contains("fetching") {
            return .cyan
        }
        return .primary
    }

    private func runDiagnostic(_ command: String) {
        manager.runDiagnosticCommand(command)
    }
}
