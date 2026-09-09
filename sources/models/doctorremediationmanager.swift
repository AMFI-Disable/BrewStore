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
        if trimmed.contains("broken symlinks") || trimmed.contains("broken symlink") {
            issues.append(
                BrewStoreDoctorIssue(
                    id: "broken_symlinks",
                    title: "Broken Symlinks in Homebrew Prefix",
                    description: "Orphaned symlinks exist in your Homebrew directory pointing to deleted files.",
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
}
