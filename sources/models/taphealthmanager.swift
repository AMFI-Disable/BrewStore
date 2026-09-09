import Combine
import Foundation

enum TapHealthStatus: String, Codable {
    case healthy = "Healthy"
    case stale = "Stale (Inactive)"
    case unverified = "Local / Unverified"
    case offline = "Unreachable"

    var badgeColorName: String {
        switch self {
        case .healthy: "green"
        case .stale: "orange"
        case .unverified: "gray"
        case .offline: "red"
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
}

@MainActor
final class BrewStoreTapHealthManager: ObservableObject {
    static let shared = BrewStoreTapHealthManager()

    @Published var reports: [String: TapHealthReport] = [:]
    @Published var isAuditing: Bool = false

    func report(for tapName: String) -> TapHealthReport? {
        reports[tapName]
    }

    func auditTap(tap: BrewStoreTap, prefix: String?) {
        let tapName = tap.name
        let localURL = resolveLocalTapDirectory(tapName: tapName, prefix: prefix)

        var remoteURL: String?
        if let localURL {
            remoteURL = parseGitRemoteURL(from: localURL)
        }

        let provider = resolveProviderName(remoteURL: remoteURL, tapName: tapName)
        let status: TapHealthStatus = tap.isOfficial ? .healthy : (remoteURL != nil ? .healthy : .unverified)

        let rep = TapHealthReport(
            tapName: tapName,
            remoteURL: remoteURL ?? "https://github.com/\(tapName)",
            hostProvider: provider,
            status: status,
            lastCheckedAt: Date(),
            notes: tap.isOfficial ? "Official Homebrew Core Repository" : nil
        )

        reports[tapName] = rep
    }

    func auditAllTaps(taps: [BrewStoreTap], prefix: String?) {
        guard !isAuditing else { return }
        isAuditing = true

        for tap in taps {
            auditTap(tap: tap, prefix: prefix)
        }

        isAuditing = false
    }

    private func resolveLocalTapDirectory(tapName: String, prefix: String?) -> URL? {
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
}
