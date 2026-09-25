import AppKit
import Combine
import Foundation
import SwiftUI

enum TapHealthStatus: String, Codable, CaseIterable {
    case healthy = "Healthy"
    case commitLag = "Behind Remote"
    case shallowWarning = "Shallow Clone"
    case highLatency = "High Latency"
    case stale = "Stale (Inactive)"
    case unverified = "Local / Unverified"
    case corrupted = "Corrupted / Detached"
    case offline = "Unreachable"

    var badgeColorName: String {
        switch self {
        case .healthy: "green"
        case .commitLag: "orange"
        case .shallowWarning: "yellow"
        case .highLatency: "orange"
        case .stale: "orange"
        case .unverified: "gray"
        case .corrupted: "red"
        case .offline: "red"
        }
    }

    var color: Color {
        switch self {
        case .healthy: .green
        case .commitLag: .orange
        case .shallowWarning: .yellow
        case .highLatency: .orange
        case .stale: .orange
        case .unverified: .gray
        case .corrupted: .red
        case .offline: .red
        }
    }

    var iconName: String {
        switch self {
        case .healthy: "checkmark.shield.fill"
        case .commitLag: "arrow.triangle.pull"
        case .shallowWarning: "square.stack.3d.down.right"
        case .highLatency: "gauge.with.needle.fill"
        case .stale: "clock.arrow.circlepath"
        case .unverified: "questionmark.circle.fill"
        case .corrupted: "exclamationmark.triangle.fill"
        case .offline: "wifi.slash"
        }
    }
}

enum TapTransportProtocol: String, Codable, CaseIterable {
    case https = "HTTPS"
    case ssh = "SSH"
    case fileOrCustom = "Local / Custom"

    var systemImage: String {
        switch self {
        case .https: "lock.shield.fill"
        case .ssh: "key.fill"
        case .fileOrCustom: "internaldrive"
        }
    }
}

struct TapHealthReport: Identifiable, Hashable, Codable {
    var id: String {
        tapName
    }

    let tapName: String
    let remoteURL: String?
    let hostProvider: String
    let status: TapHealthStatus
    let lastCheckedAt: Date
    let notes: String?
    let isOfficial: Bool
    let branch: String?
    let headCommit: String?
    let lastCommitDateString: String?
    let commitLagBehind: Int
    let commitLagAhead: Int
    let isShallow: Bool
    let transportProtocol: TapTransportProtocol
    let latencyMilliseconds: Double?
    let formulaCount: Int
    let caskCount: Int
    let commandCount: Int
    let localDirectoryPath: String?

    init(
        tapName: String,
        remoteURL: String?,
        hostProvider: String,
        status: TapHealthStatus,
        lastCheckedAt: Date = Date(),
        notes: String? = nil,
        isOfficial: Bool = false,
        branch: String? = nil,
        headCommit: String? = nil,
        lastCommitDateString: String? = nil,
        commitLagBehind: Int = 0,
        commitLagAhead: Int = 0,
        isShallow: Bool = false,
        transportProtocol: TapTransportProtocol = .https,
        latencyMilliseconds: Double? = nil,
        formulaCount: Int = 0,
        caskCount: Int = 0,
        commandCount: Int = 0,
        localDirectoryPath: String? = nil
    ) {
        self.tapName = tapName
        self.remoteURL = remoteURL
        self.hostProvider = hostProvider
        self.status = status
        self.lastCheckedAt = lastCheckedAt
        self.notes = notes
        self.isOfficial = isOfficial
        self.branch = branch
        self.headCommit = headCommit
        self.lastCommitDateString = lastCommitDateString
        self.commitLagBehind = commitLagBehind
        self.commitLagAhead = commitLagAhead
        self.isShallow = isShallow
        self.transportProtocol = transportProtocol
        self.latencyMilliseconds = latencyMilliseconds
        self.formulaCount = formulaCount
        self.caskCount = caskCount
        self.commandCount = commandCount
        self.localDirectoryPath = localDirectoryPath
    }

    var hasCommitLag: Bool {
        commitLagBehind > 0
    }

    var isHighLatency: Bool {
        (latencyMilliseconds ?? 0) > 400.0
    }

    var totalItemCount: Int {
        formulaCount + caskCount + commandCount
    }

    var formattedLatency: String {
        guard let ms = latencyMilliseconds else {
            return "N/A"
        }
        if ms < 1.0 {
            return "< 1 ms"
        }
        return String(format: "%.0f ms", ms)
    }

    var latencyColor: Color {
        guard let ms = latencyMilliseconds else { return .secondary }
        if ms < 150 { return .green }
        if ms < 400 { return .yellow }
        return .orange
    }

    var alternateProtocolURL: String? {
        guard let url = remoteURL else { return nil }
        switch transportProtocol {
        case .https:
            return BrewStoreTapHealthManager.convertRemoteURL(url, to: .ssh)
        case .ssh:
            return BrewStoreTapHealthManager.convertRemoteURL(url, to: .https)
        case .fileOrCustom:
            return nil
        }
    }

    var canSwitchProtocol: Bool {
        alternateProtocolURL != nil
    }
}

@MainActor
final class BrewStoreTapHealthManager: ObservableObject {
    static let shared = BrewStoreTapHealthManager()

    @Published var reports: [String: TapHealthReport] = [:]
    @Published var isAuditing: Bool = false
    @Published var isBenchmarking: Bool = false
    @Published var isOperating: Bool = false
    @Published var operatingTapName: String? = nil
    @Published var lastAuditDate: Date? = nil
    @Published var errorMessage: String? = nil

    private let commandExecutor: BrewStoreCommandExecutor
    private let urlSession: URLSession

    init(
        commandExecutor: BrewStoreCommandExecutor = .shared,
        urlSession: URLSession? = nil
    ) {
        self.commandExecutor = commandExecutor
        if let session = urlSession {
            self.urlSession = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4.0
            config.timeoutIntervalForResource = 4.0
            self.urlSession = URLSession(configuration: config)
        }
    }

    func report(for tapName: String) -> TapHealthReport? {
        reports[tapName]
    }

    // MARK: - Synchronous Backwards-Compatible Audit

    func auditTap(tap: BrewStoreTap, prefix: String?) {
        let tapName = tap.name
        let localURL = resolveLocalTapDirectory(tapName: tapName, prefix: prefix)

        var remoteURL: String?
        if let localURL {
            remoteURL = parseGitRemoteURL(from: localURL)
        }

        let provider = resolveProviderName(remoteURL: remoteURL, tapName: tapName)
        let resolvedRemote = remoteURL ?? "https://github.com/\(tapName)"
        let proto = Self.detectProtocol(from: resolvedRemote)

        var branch: String?
        var headCommit: String?
        var lastCommitDate: String?
        var lagBehind = 0
        var lagAhead = 0
        var isShallow = false
        var formulaCount = 0
        var caskCount = 0
        var commandCount = 0

        if let localURL {
            let shallowFile = localURL.appendingPathComponent(".git/shallow")
            isShallow = FileManager.default.fileExists(atPath: shallowFile.path)

            let branchRes = commandExecutor.run(
                executablePath: "/usr/bin/git",
                arguments: ["-C", localURL.path, "rev-parse", "--abbrev-ref", "HEAD"],
                timeout: 5,
                category: .readOnly
            )
            if branchRes.succeeded {
                let trimmed = branchRes.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                branch = trimmed.isEmpty ? nil : trimmed
            }

            let headRes = commandExecutor.run(
                executablePath: "/usr/bin/git",
                arguments: ["-C", localURL.path, "rev-parse", "--short", "HEAD"],
                timeout: 5,
                category: .readOnly
            )
            if headRes.succeeded {
                let trimmed = headRes.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                headCommit = trimmed.isEmpty ? nil : trimmed
            }

            let logRes = commandExecutor.run(
                executablePath: "/usr/bin/git",
                arguments: ["-C", localURL.path, "log", "-1", "--format=%cr"],
                timeout: 5,
                category: .readOnly
            )
            if logRes.succeeded {
                let trimmed = logRes.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                lastCommitDate = trimmed.isEmpty ? nil : trimmed
            }

            let revListRes = commandExecutor.run(
                executablePath: "/usr/bin/git",
                arguments: ["-C", localURL.path, "rev-list", "--left-right", "--count", "HEAD...@{u}"],
                timeout: 5,
                category: .readOnly
            )
            if revListRes.succeeded {
                let parsed = Self.parseAheadBehind(from: revListRes.standardOutput)
                lagAhead = parsed.ahead
                lagBehind = parsed.behind
            }

            let counts = inspectTapInventory(at: localURL)
            formulaCount = counts.formulae
            caskCount = counts.casks
            commandCount = counts.commands
        }

        let status: TapHealthStatus
        if tap.isOfficial {
            status = .healthy
        } else if localURL == nil && remoteURL == nil {
            status = .unverified
        } else if lagBehind > 0 {
            status = .commitLag
        } else if isShallow {
            status = .shallowWarning
        } else {
            status = .healthy
        }

        let rep = TapHealthReport(
            tapName: tapName,
            remoteURL: resolvedRemote,
            hostProvider: provider,
            status: status,
            lastCheckedAt: Date(),
            notes: tap.isOfficial ? "Official Homebrew Core Repository" : nil,
            isOfficial: tap.isOfficial,
            branch: branch,
            headCommit: headCommit,
            lastCommitDateString: lastCommitDate,
            commitLagBehind: lagBehind,
            commitLagAhead: lagAhead,
            isShallow: isShallow,
            transportProtocol: proto,
            latencyMilliseconds: reports[tapName]?.latencyMilliseconds,
            formulaCount: formulaCount,
            caskCount: caskCount,
            commandCount: commandCount,
            localDirectoryPath: localURL?.path
        )

        reports[tapName] = rep
        lastAuditDate = Date()
    }

    func auditAllTaps(taps: [BrewStoreTap], prefix: String?) {
        guard !isAuditing else { return }
        isAuditing = true

        for tap in taps {
            auditTap(tap: tap, prefix: prefix)
        }

        isAuditing = false
    }

    // MARK: - Asynchronous Deep Audit with Remote Latency

    func auditAllTapsAsync(taps: [BrewStoreTap], prefix: String?) async {
        guard !isAuditing else { return }
        isAuditing = true
        defer { isAuditing = false }

        for tap in taps {
            auditTap(tap: tap, prefix: prefix)
        }

        await benchmarkAllLatencies()
    }

    // MARK: - Latency Benchmarking

    func benchmarkLatency(for tapName: String) async -> Double? {
        guard let report = reports[tapName], let remoteURL = report.remoteURL else { return nil }

        let testEndpoint = Self.resolveLatencyProbeURL(from: remoteURL)
        guard let targetURL = URL(string: testEndpoint) else { return nil }

        var request = URLRequest(url: targetURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3.5

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await urlSession.data(for: request)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

            let updatedStatus: TapHealthStatus
            if report.status == .healthy && elapsedMs > 400.0 {
                updatedStatus = .highLatency
            } else if report.status == .highLatency && elapsedMs <= 400.0 {
                updatedStatus = .healthy
            } else {
                updatedStatus = report.status
            }

            let updatedReport = TapHealthReport(
                tapName: report.tapName,
                remoteURL: report.remoteURL,
                hostProvider: report.hostProvider,
                status: updatedStatus,
                lastCheckedAt: Date(),
                notes: report.notes,
                isOfficial: report.isOfficial,
                branch: report.branch,
                headCommit: report.headCommit,
                lastCommitDateString: report.lastCommitDateString,
                commitLagBehind: report.commitLagBehind,
                commitLagAhead: report.commitLagAhead,
                isShallow: report.isShallow,
                transportProtocol: report.transportProtocol,
                latencyMilliseconds: elapsedMs,
                formulaCount: report.formulaCount,
                caskCount: report.caskCount,
                commandCount: report.commandCount,
                localDirectoryPath: report.localDirectoryPath
            )
            reports[tapName] = updatedReport
            return elapsedMs
        } catch {
            let updatedStatus: TapHealthStatus = (report.status == .healthy || report.status == .highLatency) ? .offline : report.status
            let updatedReport = TapHealthReport(
                tapName: report.tapName,
                remoteURL: report.remoteURL,
                hostProvider: report.hostProvider,
                status: updatedStatus,
                lastCheckedAt: Date(),
                notes: report.notes,
                isOfficial: report.isOfficial,
                branch: report.branch,
                headCommit: report.headCommit,
                lastCommitDateString: report.lastCommitDateString,
                commitLagBehind: report.commitLagBehind,
                commitLagAhead: report.commitLagAhead,
                isShallow: report.isShallow,
                transportProtocol: report.transportProtocol,
                latencyMilliseconds: nil,
                formulaCount: report.formulaCount,
                caskCount: report.caskCount,
                commandCount: report.commandCount,
                localDirectoryPath: report.localDirectoryPath
            )
            reports[tapName] = updatedReport
            return nil
        }
    }

    func benchmarkAllLatencies() async {
        guard !isBenchmarking else { return }
        isBenchmarking = true
        defer { isBenchmarking = false }

        let tapNames = Array(reports.keys)
        await withTaskGroup(of: Void.self) { group in
            for tapName in tapNames {
                group.addTask { @MainActor in
                    _ = await self.benchmarkLatency(for: tapName)
                }
            }
        }
    }

    // MARK: - Governance Actions

    func syncTap(tapName: String, prefix: String?) async -> (success: Bool, message: String) {
        guard !isOperating else { return (false, "Another tap operation is currently in progress.") }
        isOperating = true
        operatingTapName = tapName
        defer {
            isOperating = false
            operatingTapName = nil
        }

        guard let localURL = resolveLocalTapDirectory(tapName: tapName, prefix: prefix) else {
            return (false, "Local repository directory not found for tap '\(tapName)'.")
        }

        let result = commandExecutor.run(
            executablePath: "/usr/bin/git",
            arguments: ["-C", localURL.path, "pull", "--prune"],
            timeout: 60,
            category: .reversibleMutation
        )

        if result.succeeded {
            auditTap(tap: BrewStoreTap(id: tapName, name: tapName), prefix: prefix)
            return (true, "Synchronized tap '\(tapName)' with upstream origin.")
        } else {
            let errorText = result.standardError.isEmpty ? result.standardOutput : result.standardError
            return (false, "Sync failed for '\(tapName)': \(errorText)")
        }
    }

    func repairTap(tapName: String, prefix: String?, manager: HomebrewManager? = nil) async -> (success: Bool, message: String) {
        guard !isOperating else { return (false, "Another tap operation is currently in progress.") }
        isOperating = true
        operatingTapName = tapName
        defer {
            isOperating = false
            operatingTapName = nil
        }

        let brewPath = manager?.brewPath ?? resolveBrewBinary(prefix: prefix)
        let result = commandExecutor.run(
            executablePath: brewPath,
            arguments: ["tap", "--repair", tapName],
            timeout: 90,
            category: .reversibleMutation
        )

        if result.succeeded {
            auditTap(tap: BrewStoreTap(id: tapName, name: tapName), prefix: prefix)
            return (true, "Repaired tap '\(tapName)' successfully.")
        } else {
            let errorText = result.standardError.isEmpty ? result.standardOutput : result.standardError
            return (false, "Repair failed for '\(tapName)': \(errorText)")
        }
    }

    func switchProtocol(
        tapName: String,
        to targetProtocol: TapTransportProtocol,
        prefix: String?
    ) async -> (success: Bool, message: String) {
        guard !isOperating else { return (false, "Another tap operation is currently in progress.") }
        isOperating = true
        operatingTapName = tapName
        defer {
            isOperating = false
            operatingTapName = nil
        }

        guard let localURL = resolveLocalTapDirectory(tapName: tapName, prefix: prefix) else {
            return (false, "Local repository directory not found for tap '\(tapName)'.")
        }

        guard let report = reports[tapName], let currentRemote = report.remoteURL else {
            return (false, "Remote origin URL could not be resolved for '\(tapName)'.")
        }

        guard let newURL = Self.convertRemoteURL(currentRemote, to: targetProtocol) else {
            return (false, "Unable to convert remote URL to \(targetProtocol.rawValue).")
        }

        let result = commandExecutor.run(
            executablePath: "/usr/bin/git",
            arguments: ["-C", localURL.path, "remote", "set-url", "origin", newURL],
            timeout: 10,
            category: .reversibleMutation
        )

        if result.succeeded {
            auditTap(tap: BrewStoreTap(id: tapName, name: tapName), prefix: prefix)
            return (true, "Updated remote origin of '\(tapName)' to \(newURL).")
        } else {
            let errorText = result.standardError.isEmpty ? result.standardOutput : result.standardError
            return (false, "Failed to update git remote: \(errorText)")
        }
    }

    func batchSyncAllOutdatedTaps(prefix: String?) async -> (succeeded: [String], failed: [String]) {
        let laggingTaps = reports.values.filter { $0.commitLagBehind > 0 }.map(\.tapName)
        var succeeded: [String] = []
        var failed: [String] = []

        for name in laggingTaps {
            let res = await syncTap(tapName: name, prefix: prefix)
            if res.success {
                succeeded.append(name)
            } else {
                failed.append(name)
            }
        }

        return (succeeded, failed)
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Internal Helpers & Parsers

    func resolveLocalTapDirectory(tapName: String, prefix: String?) -> URL? {
        let basePrefix = prefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let parts = tapName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let user = String(parts[0])
        let repo = String(parts[1])
        let repoName = repo.hasPrefix("homebrew-") ? repo : "homebrew-\(repo)"

        let candidate = URL(fileURLWithPath: basePrefix)
            .appendingPathComponent("Library/Taps", isDirectory: true)
            .appendingPathComponent(user, isDirectory: true)
            .appendingPathComponent(repoName, isDirectory: true)

        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func resolveBrewBinary(prefix: String?) -> String {
        let basePrefix = prefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let candidate = URL(fileURLWithPath: basePrefix).appendingPathComponent("bin/brew").path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : "/usr/local/bin/brew"
    }

    private func parseGitRemoteURL(from localTapURL: URL) -> String? {
        let configURL = localTapURL.appendingPathComponent(".git/config")
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("url = ") {
                return trimmed.replacingOccurrences(of: "url = ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func resolveProviderName(remoteURL: String?, tapName _: String) -> String {
        guard let url = remoteURL?.lowercased() else { return "GitHub" }
        if url.contains("gitlab") {
            return "GitLab"
        }
        if url.contains("codeberg") {
            return "Codeberg"
        }
        if url.contains("gitea") || url.contains("forgejo") {
            return "Forgejo / Gitea"
        }
        if url.contains("github") {
            return "GitHub"
        }
        return "Self-Hosted Git"
    }

    private func inspectTapInventory(at localURL: URL) -> (formulae: Int, casks: Int, commands: Int) {
        var formulae = 0
        var casks = 0
        var commands = 0

        let fm = FileManager.default

        // Formula directory & root .rb
        let formulaDir = localURL.appendingPathComponent("Formula")
        if let items = try? fm.contentsOfDirectory(atPath: formulaDir.path) {
            formulae += items.filter { $0.hasSuffix(".rb") }.count
        }
        if let rootItems = try? fm.contentsOfDirectory(atPath: localURL.path) {
            formulae += rootItems.filter { $0.hasSuffix(".rb") }.count
        }

        // Casks directory
        let caskDir = localURL.appendingPathComponent("Casks")
        if let items = try? fm.contentsOfDirectory(atPath: caskDir.path) {
            casks += items.filter { $0.hasSuffix(".rb") }.count
        }

        // Commands directory
        let cmdDir = localURL.appendingPathComponent("cmd")
        if let items = try? fm.contentsOfDirectory(atPath: cmdDir.path) {
            commands += items.filter { $0.hasSuffix(".rb") }.count
        }

        return (formulae, casks, commands)
    }

    // MARK: - Static Parser Helpers

    nonisolated static func detectProtocol(from urlString: String) -> TapTransportProtocol {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("git@") || trimmed.hasPrefix("ssh://") {
            return .ssh
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return .https
        }
        return .fileOrCustom
    }

    nonisolated static func resolveLatencyProbeURL(from remoteURL: String) -> String {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            if let url = URL(string: trimmed), let host = url.host {
                return "https://\(host)"
            }
            return trimmed
        }
        if trimmed.hasPrefix("git@") {
            let withoutGit = trimmed.replacingOccurrences(of: "git@", with: "")
            let components = withoutGit.split(separator: ":", maxSplits: 1)
            if let host = components.first {
                return "https://\(host)"
            }
        }
        return "https://github.com"
    }

    nonisolated static func convertRemoteURL(_ urlString: String, to target: TapTransportProtocol) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch target {
        case .ssh:
            if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
                guard let url = URL(string: trimmed), let host = url.host else { return nil }
                var path = url.path
                if path.hasPrefix("/") { path.removeFirst() }
                if !path.hasSuffix(".git") { path += ".git" }
                return "git@\(host):\(path)"
            }
            return trimmed.hasSuffix(".git") ? trimmed : "\(trimmed).git"

        case .https:
            if trimmed.hasPrefix("git@") {
                let withoutGit = trimmed.replacingOccurrences(of: "git@", with: "")
                let components = withoutGit.split(separator: ":", maxSplits: 1)
                guard components.count == 2 else { return nil }
                let host = String(components[0])
                var path = String(components[1])
                if !path.hasSuffix(".git") { path += ".git" }
                return "https://\(host)/\(path)"
            } else if trimmed.hasPrefix("ssh://git@") {
                let withoutPrefix = trimmed.replacingOccurrences(of: "ssh://git@", with: "")
                let components = withoutPrefix.split(separator: "/", maxSplits: 1)
                guard components.count == 2 else { return nil }
                let host = String(components[0])
                var path = String(components[1])
                if !path.hasSuffix(".git") { path += ".git" }
                return "https://\(host)/\(path)"
            }
            return trimmed

        case .fileOrCustom:
            return trimmed
        }
    }

    nonisolated static func parseAheadBehind(from revListOutput: String) -> (ahead: Int, behind: Int) {
        let parts = revListOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard parts.count >= 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else {
            return (0, 0)
        }
        return (ahead, behind)
    }
}
