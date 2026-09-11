import Foundation
import SwiftUI

struct BrewStoreServiceLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let text: String
    let isError: Bool

    init(timestamp: Date = Date(), text: String, isError: Bool = false) {
        self.timestamp = timestamp
        self.text = text
        self.isError = isError
    }
}

@MainActor
final class BrewStoreServiceLogManager: ObservableObject {
    static let shared = BrewStoreServiceLogManager()

    @Published var logEntries: [BrewStoreServiceLogEntry] = []
    @Published var activeServiceName: String?
    @Published var logFilePath: String?
    @Published var isStreaming = false

    private var fileWatcherTask: Task<Void, Never>?

    init() {}

    nonisolated static func candidateLogPaths(for serviceName: String, prefix: String = "/opt/homebrew") -> [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let cleanName = serviceName.components(separatedBy: "@").first ?? serviceName

        return [
            "\(prefix)/var/log/\(serviceName).log",
            "\(prefix)/var/log/\(serviceName).error.log",
            "\(prefix)/var/log/\(cleanName).log",
            "\(prefix)/var/log/\(cleanName)/error.log",
            "\(prefix)/var/log/\(cleanName)/current.log",
            "\(homeDir)/Library/Logs/Homebrew/\(serviceName).log",
            "\(homeDir)/Library/Logs/\(serviceName).log",
            "/usr/local/var/log/\(serviceName).log"
        ]
    }

    static func resolveLogFile(for serviceName: String, manager: HomebrewManager) -> String? {
        let prefix = manager.brewPrefix ?? "/opt/homebrew"
        let candidates = candidateLogPaths(for: serviceName, prefix: prefix)

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    func startStreaming(serviceName: String, manager: HomebrewManager) {
        stopStreaming()

        activeServiceName = serviceName
        isStreaming = true

        let resolved = Self.resolveLogFile(for: serviceName, manager: manager)
        logFilePath = resolved

        guard let path = resolved, FileManager.default.fileExists(atPath: path) else {
            logEntries = [
                BrewStoreServiceLogEntry(
                    text: "No active log file found on disk for service `\(serviceName)`. Service may log to system Unified Logging or standard output.",
                    isError: false
                )
            ]
            return
        }

        logEntries = []

        fileWatcherTask = Task { [weak self] in
            let initialEntries = await Task.detached(priority: .background) {
                Self.readTailEntries(filePath: path)
            }.value
            guard let self else { return }
            self.logEntries = initialEntries

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                let entries = await Task.detached(priority: .background) {
                    Self.readTailEntries(filePath: path)
                }.value
                guard !Task.isCancelled else { break }
                self.logEntries = entries
            }
        }
    }

    func stopStreaming() {
        fileWatcherTask?.cancel()
        fileWatcherTask = nil
        isStreaming = false
    }

    nonisolated static func readTailEntries(filePath: String, maxBytes: Int = 128 * 1024, maxLines: Int = 100) -> [BrewStoreServiceLogEntry] {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: filePath)) else {
            return []
        }
        defer { try? handle.close() }

        let data: Data
        do {
            let fileSize = try handle.seekToEnd()
            let offsetToSeek = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
            try handle.seek(toOffset: offsetToSeek)
            data = handle.readDataToEndOfFile()
        } catch {
            return []
        }

        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return []
        }

        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let tailLines = lines.suffix(maxLines)

        return tailLines.map { line in
            let isErr = line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("fatal")
            return BrewStoreServiceLogEntry(text: line, isError: isErr)
        }
    }

    func clear() {
        logEntries.removeAll()
    }
}
