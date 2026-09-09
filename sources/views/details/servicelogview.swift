import AppKit
import SwiftUI

struct ServiceLogView: View {
    @Environment(\.dismiss) private var dismiss
    let service: BrewStoreService
    let brewPrefix: String?
    @State private var logContent = ""
    @State private var search = ""
    @State private var isAutoRefresh = true
    @State private var timerTask: Task<Void, Never>?
    @State private var copied = false

    private var logURL: URL? {
        if let direct = service.logURL(prefix: brewPrefix), FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        let prefix = brewPrefix ?? "/opt/homebrew"
        if let resolved = BrewStoreServiceLogManager.candidateLogPaths(for: service.name, prefix: prefix).first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return URL(fileURLWithPath: resolved)
        }
        return service.logURL(prefix: brewPrefix)
    }

    private var configURL: URL? {
        service.configURL(prefix: brewPrefix)
    }

    private var filteredLines: [String] {
        let lines = logContent.components(separatedBy: .newlines)
        if search.isEmpty {
            return lines
        }
        return lines.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("\(service.name) Service Logs").font(.title2.bold())
                        Text(service.status)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(service.isRunning ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(service.isRunning ? Color.green : Color.secondary)
                    }

                    if let path = logURL?.path {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let logURL, FileManager.default.fileExists(atPath: logURL.path) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([logURL])
                    }
                    .controlSize(.small)
                }

                if let configURL {
                    Button("Open Config") {
                        NSWorkspace.shared.open(configURL)
                    }
                    .controlSize(.small)
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()

            Divider()

            // Toolbar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter logs…", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 240)

                Toggle("Auto-refresh", isOn: $isAutoRefresh)
                    .controlSize(.small)

                Spacer()

                Text("\(filteredLines.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(copied ? "Copied!" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logContent, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                .controlSize(.small)

                Button(action: readLogs) {
                    Image(systemName: "arrow.clockwise")
                }
                .controlSize(.small)
                .help("Refresh log now")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.04))

            Divider()

            // Content
            if logContent.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No logs available yet")
                        .font(.headline)
                    if let path = logURL?.path {
                        Text("Log file: \(path)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { _ in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 36, alignment: .trailing)
                                    Text(line.isEmpty ? " " : line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(line.lowercased().contains("error") ? Color.red : (line.lowercased().contains("warn") ? Color.orange : Color.primary))
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                                .id(index)
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear {
            readLogs()
            startAutoRefreshTimer()
        }
        .onDisappear {
            timerTask?.cancel()
        }
    }

    private func readLogs() {
        guard let url = logURL, FileManager.default.fileExists(atPath: url.path) else {
            logContent = ""
            return
        }

        Task.detached(priority: .userInitiated) {
            if let data = try? Data(contentsOf: url),
               let string = String(data: data, encoding: .utf8) {
                // Keep latest 2000 lines if very large
                let lines = string.components(separatedBy: .newlines)
                let trimmed = lines.suffix(2000).joined(separator: "\n")
                await MainActor.run {
                    self.logContent = trimmed
                }
            }
        }
    }

    private func startAutoRefreshTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard isAutoRefresh, !Task.isCancelled else { continue }
                await MainActor.run {
                    self.readLogs()
                }
            }
        }
    }
}
