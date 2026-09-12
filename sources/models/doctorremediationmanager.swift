import Foundation
import SwiftUI

struct BrewStoreDoctorIssue: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let severity: Severity
    let fixActionTitle: String?
    let fixCommandArgs: [String]?

    enum Severity: String, Sendable {
        case warning = "Warning"
        case info = "Info"
        case suggestion = "Suggestion"

        var color: Color {
            switch self {
            case .warning: .orange
            case .info: .blue
            case .suggestion: .purple
            }
        }

        var icon: String {
            switch self {
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            case .suggestion: "lightbulb.fill"
            }
        }
    }

    init(
        id: String,
        title: String,
        description: String,
        severity: Severity = .warning,
        fixActionTitle: String? = nil,
        fixCommandArgs: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.severity = severity
        self.fixActionTitle = fixActionTitle
        self.fixCommandArgs = fixCommandArgs
    }
}

@MainActor
final class BrewStoreDoctorRemediationManager: ObservableObject {
    static let shared = BrewStoreDoctorRemediationManager()

    @Published var isFixing = false
    @Published var lastFixOutput: String?
    @Published var activeFixIssueID: String?

    init() {}

    func analyzeIssues(rawDoctorOutput: String, packages: [BrewStorePackage]) -> [BrewStoreDoctorIssue] {
        var issues: [BrewStoreDoctorIssue] = []

        let trimmed = rawDoctorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("Your system is ready to brew") {
            return []
        }

        // 1. Unlinked kegs warning
        if trimmed.contains("unlinked kegs") || trimmed.contains("brew link") {
            issues.append(
                BrewStoreDoctorIssue(
                    id: "unlinked_kegs",
                    title: "Unlinked Formulae Detected",
                    description: "Some installed packages are not linked into your PATH. Running `brew cleanup` or linking will resolve binary lookup issues.",
                    severity: .warning,
                    fixActionTitle: "Prune & Clean Broken Links",
                    fixCommandArgs: ["cleanup", "--prune=all"]
                )
            )
        }

        // 2. Broken Symlinks or uncommitted taps
        let danglingLinks = scanDanglingSymlinks()
        if !danglingLinks.isEmpty || trimmed.contains("broken symlinks") || trimmed.contains("broken symlink") {
            let desc = !danglingLinks.isEmpty
                ? "Found \(danglingLinks.count) orphaned symlink(s) in Homebrew binary paths (e.g. \(danglingLinks.prefix(3).map(\.lastPathComponent).joined(separator: ", ")))."
                : "Orphaned symlinks exist in your Homebrew directory pointing to deleted files."
            issues.append(
                BrewStoreDoctorIssue(
                    id: "broken_symlinks",
                    title: "Broken Symlinks in Homebrew Prefix",
                    description: desc,
                    severity: .warning,
                    fixActionTitle: "Prune Broken Symlinks",
                    fixCommandArgs: ["cleanup", "-s"]
                )
            )
        }

        // 3. Cache buildup suggestion
        issues.append(
            BrewStoreDoctorIssue(
                id: "cache_pruning",
                title: "Download Cache Maintenance",
                description: "Reclaim disk space by cleaning old download caches and lockfiles.",
                severity: .suggestion,
                fixActionTitle: "Clear Old Download Caches",
                fixCommandArgs: ["cleanup", "--prune=30"]
            )
        )

        // 4. Missing dependencies
        let installed = packages.filter(\.isInstalled)
        let installedIDs = Set(installed.map { $0.id.lowercased() })
        var missingDeps: [String] = []
        for pkg in installed {
            for dep in pkg.dependencies {
                if !installedIDs.contains(dep.lowercased()) {
                    missingDeps.append(dep)
                }
            }
        }

        if !missingDeps.isEmpty {
            let uniqueMissing = Array(Set(missingDeps)).sorted()
            issues.append(
                BrewStoreDoctorIssue(
                    id: "missing_deps",
                    title: "Missing Dependency Binaries",
                    description: "Some installed packages depend on: \(uniqueMissing.prefix(5).joined(separator: ", ")) which are currently missing.",
                    severity: .warning,
                    fixActionTitle: "Check Dependencies (brew missing)",
                    fixCommandArgs: ["missing"]
                )
            )
        }

        return issues
    }

    func executeFix(
        issue: BrewStoreDoctorIssue,
        manager: HomebrewManager,
        completion: @escaping (Bool) -> Void
    ) {
        guard let brewPath = manager.brewPath,
              let args = issue.fixCommandArgs,
              !args.isEmpty
        else {
            completion(false)
            return
        }

        isFixing = true
        activeFixIssueID = issue.id

        Task.detached(priority: .userInitiated) {
            let result = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: args,
                timeout: 60,
                category: .reversibleMutation
            )

            await MainActor.run {
                self.isFixing = false
                self.activeFixIssueID = nil
                self.lastFixOutput = result.succeeded
                    ? "Successfully ran `brew \(args.joined(separator: " "))`"
                    : "Fix command failed: \(result.standardError)"
                manager.refresh()
                completion(result.succeeded)
            }
        }
    }

    nonisolated func scanDanglingSymlinks(prefixPath: String? = nil) -> [URL] {
        let fm = FileManager.default
        let prefix = prefixPath ?? (fm.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let candidateDirs = [
            URL(fileURLWithPath: prefix).appendingPathComponent("bin", isDirectory: true),
            URL(fileURLWithPath: prefix).appendingPathComponent("sbin", isDirectory: true)
        ]

        var dangling: [URL] = []

        for dir in candidateDirs {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles) else {
                continue
            }
            for url in contents {
                guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true else {
                    continue
                }
                if let dest = try? fm.destinationOfSymbolicLink(atPath: url.path) {
                    let destURL = dest.hasPrefix("/") ? URL(fileURLWithPath: dest) : url.deletingLastPathComponent().appendingPathComponent(dest)
                    if !fm.fileExists(atPath: destURL.path) {
                        dangling.append(url)
                    }
                }
            }
        }

        return dangling
    }

    nonisolated func pruneBrokenSymlinks(links: [URL]) -> (removed: Int, errors: [String]) {
        let fm = FileManager.default
        var removedCount = 0
        var errors: [String] = []

        for link in links {
            do {
                try fm.removeItem(at: link)
                removedCount += 1
            } catch {
                errors.append("Failed to remove \(link.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (removedCount, errors)
    }
}
