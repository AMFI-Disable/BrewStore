import AppKit
import Foundation

struct ToolchainIssue: Identifiable, Hashable, Codable {
    enum IssueKind: String, Codable {
        case orphan = "Orphaned Dependency"
        case unlinked = "Unlinked Formula"
        case missing = "Missing Dependency"
        case doctor = "Doctor Diagnostic"
    }

    var id: String
    var title: String
    var description: String
    var kind: IssueKind
    var severity: String
    var recommendedAction: String
    var packageID: String?
}

struct ToolchainDiagnosisReport: Hashable, Codable {
    let issues: [ToolchainIssue]
    let score: Int
    let grade: String
    let summary: String

    var orphanCount: Int {
        issues.filter { $0.kind == .orphan }.count
    }

    var unlinkedCount: Int {
        issues.filter { $0.kind == .unlinked }.count
    }

    var missingCount: Int {
        issues.filter { $0.kind == .missing }.count
    }
}

@MainActor
final class BrewStoreDependencyDoctorManager: ObservableObject {
    static let shared = BrewStoreDependencyDoctorManager()

    @Published var report: ToolchainDiagnosisReport?
    @Published var isDiagnosing = false
    @Published var isHealing = false
    @Published var healStatusMessage: String?

    func diagnose(manager: HomebrewManager) {
        isDiagnosing = true
        let prefix = manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let brewPath = manager.brewPath

        Task.detached(priority: .userInitiated) {
            var foundIssues: [ToolchainIssue] = []

            // 1. Scan unlinked Cellar formulae
            let fm = FileManager.default
            let cellarURL = URL(fileURLWithPath: prefix).appendingPathComponent("Cellar")
            let binURL = URL(fileURLWithPath: prefix).appendingPathComponent("bin")

            if let cellarDirs = try? fm.contentsOfDirectory(at: cellarURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for dir in cellarDirs {
                    let pkgName = dir.lastPathComponent
                    // Check if binary exists in bin/
                    let targetBin = binURL.appendingPathComponent(pkgName)
                    if !fm.fileExists(atPath: targetBin.path) {
                        // Check if formula has bin directory inside version
                        if let versionDirs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                            let validVersions = versionDirs.filter { !$0.lastPathComponent.hasPrefix(".") }
                            if let latest = validVersions.first {
                                let innerBin = latest.appendingPathComponent("bin/\(pkgName)")
                                if fm.fileExists(atPath: innerBin.path) {
                                    foundIssues.append(ToolchainIssue(
                                        id: "unlinked-\(pkgName)",
                                        title: "Unlinked Formula: \(pkgName)",
                                        description: "Formula is installed in Cellar but its executable is not symlinked to \(prefix)/bin.",
                                        kind: .unlinked,
                                        severity: "warning",
                                        recommendedAction: "Link Formula",
                                        packageID: pkgName
                                    ))
                                }
                            }
                        }
                    }
                }
            }

            // 2. Scan dangling symlinks
            let dangling = BrewStoreDoctorRemediationManager.shared.scanDanglingSymlinks(prefixPath: prefix)
            if !dangling.isEmpty {
                let count = dangling.count
                let names = dangling.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
                foundIssues.append(ToolchainIssue(
                    id: "broken-symlinks",
                    title: "Broken Symlinks (\(count) found)",
                    description: "Orphaned symlinks in \(prefix)/bin pointing to missing files: \(names)",
                    kind: .doctor,
                    severity: "warning",
                    recommendedAction: "Prune Broken Symlinks",
                    packageID: nil
                ))
            }

            // 3. Scan missing dependencies if brew available
            if let brewPath {
                let missingResult = BrewStoreCommandExecutor.shared.run(
                    executablePath: brewPath,
                    arguments: ["missing"],
                    timeout: 45,
                    category: .readOnly
                )

                if missingResult.succeeded, !missingResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    for line in missingResult.standardOutput.components(separatedBy: .newlines) where !line.isEmpty {
                        let parts = line.split(separator: ":")
                        let pkg = parts.first.map(String.init) ?? line
                        foundIssues.append(ToolchainIssue(
                            id: "missing-\(pkg)",
                            title: "Missing Runtime Dependency for \(pkg)",
                            description: line,
                            kind: .missing,
                            severity: "critical",
                            recommendedAction: "Install Dependencies",
                            packageID: pkg
                        ))
                    }
                }

                // 4. Scan autoremove orphans (dry-run)
                let autoResult = BrewStoreCommandExecutor.shared.run(
                    executablePath: brewPath,
                    arguments: ["autoremove", "-n"],
                    timeout: 45,
                    category: .readOnly
                )

                if autoResult.succeeded {
                    for line in autoResult.standardOutput.components(separatedBy: .newlines) where line.contains("Uninstalling") || line.contains("uninstall") {
                        let tokens = line.split(separator: " ")
                        if let target = tokens.last.map(String.init), !target.isEmpty {
                            foundIssues.append(ToolchainIssue(
                                id: "orphan-\(target)",
                                title: "Orphaned Package: \(target)",
                                description: "Installed as a dependency, but no longer required by any installed package.",
                                kind: .orphan,
                                severity: "info",
                                recommendedAction: "Prune Orphan",
                                packageID: target
                            ))
                        }
                    }
                }
            }

            // Calculate Score & Grade
            let score = max(20, 100 - (foundIssues.count * 12))
            let grade: String = switch score {
            case 90 ... 100: "A+"
            case 80 ..< 90: "A"
            case 70 ..< 80: "B"
            case 60 ..< 70: "C"
            default: "F"
            }

            let summary = foundIssues.isEmpty ? "All dependencies, symlinks, and runtimes are healthy." : "\(foundIssues.count) issues found."

            let reportResult = ToolchainDiagnosisReport(
                issues: foundIssues,
                score: score,
                grade: grade,
                summary: summary
            )

            await MainActor.run {
                self.report = reportResult
                self.isDiagnosing = false
            }
        }
    }

    func autoHealToolchain(manager: HomebrewManager) {
        guard let brewPath = manager.brewPath else { return }
        let prefix = manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        isHealing = true
        healStatusMessage = "Starting maintenance repairs…"

        Task.detached(priority: .userInitiated) {
            // Step 1: Link broken formulae
            await MainActor.run { self.healStatusMessage = "Step 1/4: Repairing broken symlinks…" }
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["link", "--overwrite", "--quiet"],
                timeout: 60,
                category: .reversibleMutation
            )

            // Step 2: Prune dangling symlinks
            await MainActor.run { self.healStatusMessage = "Step 2/4: Pruning orphaned symlinks…" }
            let broken = BrewStoreDoctorRemediationManager.shared.scanDanglingSymlinks(prefixPath: prefix)
            _ = BrewStoreDoctorRemediationManager.shared.pruneBrokenSymlinks(links: broken)

            // Step 3: Prune orphans
            await MainActor.run { self.healStatusMessage = "Step 3/4: Removing unused dependencies…" }
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["autoremove"],
                timeout: 120,
                category: .reversibleMutation
            )

            // Step 4: Run cleanup
            await MainActor.run { self.healStatusMessage = "Step 4/4: Cleaning download caches…" }
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["cleanup", "-s"],
                timeout: 120,
                category: .reversibleMutation
            )

            await MainActor.run {
                self.healStatusMessage = "Repairs completed successfully!"
                self.isHealing = false
                self.diagnose(manager: manager)
                manager.refresh()
            }
        }
    }

    func pruneDanglingSymlinks(manager: HomebrewManager, prefixPath: String? = nil) {
        let prefix = prefixPath ?? manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let broken = BrewStoreDoctorRemediationManager.shared.scanDanglingSymlinks(prefixPath: prefix)
        _ = BrewStoreDoctorRemediationManager.shared.pruneBrokenSymlinks(links: broken)
        diagnose(manager: manager)
        manager.refresh()
    }

    func fixIssue(_ issue: ToolchainIssue, manager: HomebrewManager) {
        if issue.id == "broken-symlinks" {
            pruneDanglingSymlinks(manager: manager)
            return
        }
        guard let brewPath = manager.brewPath, let pkgID = issue.packageID else { return }
        Task.detached(priority: .userInitiated) {
            var args: [String] = []
            switch issue.kind {
            case .unlinked:
                args = ["link", "--overwrite", pkgID]
            case .orphan:
                args = ["uninstall", pkgID]
            case .missing:
                args = ["install", pkgID]
            case .doctor:
                args = ["doctor"]
            }
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: args,
                timeout: 180,
                category: .reversibleMutation
            )

            await MainActor.run {
                self.diagnose(manager: manager)
            }
        }
    }
}
