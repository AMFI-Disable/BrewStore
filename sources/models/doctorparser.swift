import Foundation

enum DoctorFaultDomain: String, Codable, CaseIterable {
    case linkage = "Linkage & PATH"
    case brokenSymlinks = "Broken Symlinks"
    case gitRepository = "Git Repositories"
    case developerTools = "Xcode & Compilers"
    case permissions = "Filesystem Permissions"
    case shallowClone = "Shallow Taps"
    case cacheBuildup = "Cache & Storage"
    case missingDeps = "Dependencies"
    case general = "General Configuration"

    var iconName: String {
        switch self {
        case .linkage: "link"
        case .brokenSymlinks: "link.badge.plus"
        case .gitRepository: "arrow.triangle.branch"
        case .developerTools: "hammer.fill"
        case .permissions: "lock.shield.fill"
        case .shallowClone: "arrow.down.to.line.compact"
        case .cacheBuildup: "internaldrive.fill"
        case .missingDeps: "puzzlepiece.fill"
        case .general: "stethoscope"
        }
    }
}

enum RemediationSafetyLevel: String, Codable {
    case safeToAutoFix = "Safe Auto-Remediation"
    case requiresReview = "Requires User Review"
    case manualIntervention = "Manual Intervention Required"

    var badgeText: String {
        rawValue
    }
}

struct BrewStoreDoctorDiagnostic: Identifiable, Hashable, Codable {
    let id: String
    let severity: Severity
    let title: String
    let message: String
    let suggestedCommand: String?
    let isAutoFixable: Bool
    let autoFixCommand: String?
    let requiresSudo: Bool
    let faultDomain: DoctorFaultDomain
    let impactExplanation: String
    let potentialFallout: String
    let safetyLevel: RemediationSafetyLevel
    let dryRunCommand: String?

    enum Severity: String, Codable {
        case warning = "Warning"
        case error = "Error"
        case clean = "Clean"
    }

    init(
        id: String,
        severity: Severity,
        title: String,
        message: String,
        suggestedCommand: String? = nil,
        isAutoFixable: Bool = false,
        autoFixCommand: String? = nil,
        requiresSudo: Bool = false,
        faultDomain: DoctorFaultDomain = .general,
        impactExplanation: String = "",
        potentialFallout: String = "",
        safetyLevel: RemediationSafetyLevel = .requiresReview,
        dryRunCommand: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.suggestedCommand = suggestedCommand
        self.isAutoFixable = isAutoFixable
        self.autoFixCommand = autoFixCommand
        self.requiresSudo = requiresSudo
        self.faultDomain = faultDomain
        self.impactExplanation = impactExplanation.isEmpty ? "System configuration inconsistency detected by Homebrew Doctor." : impactExplanation
        self.potentialFallout = potentialFallout.isEmpty ? "May degrade Homebrew build operations or binary execution." : potentialFallout
        self.safetyLevel = safetyLevel
        self.dryRunCommand = dryRunCommand
    }
}

enum BrewStoreDoctorParser {
    static func parse(_ output: String) -> [BrewStoreDoctorDiagnostic] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.contains("Your system is ready to brew.") {
            return [
                BrewStoreDoctorDiagnostic(
                    id: "clean",
                    severity: .clean,
                    title: "System Ready",
                    message: "Your system is ready to brew. No issues were found.",
                    suggestedCommand: nil,
                    isAutoFixable: false,
                    autoFixCommand: nil,
                    requiresSudo: false,
                    faultDomain: .general,
                    impactExplanation: "All Homebrew paths, permissions, and toolchains are in optimal condition.",
                    potentialFallout: "None. System is running at peak health.",
                    safetyLevel: .safeToAutoFix,
                    dryRunCommand: nil
                )
            ]
        }

        var diagnostics: [BrewStoreDoctorDiagnostic] = []
        let rawChunks = trimmed.components(separatedBy: "\n\n")

        for (index, chunk) in rawChunks.enumerated() {
            let lines = chunk.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }

            var title = lines[0]
            var severity: BrewStoreDoctorDiagnostic.Severity = .warning

            if title.hasPrefix("Warning:") {
                title = String(title.dropFirst("Warning:".count)).trimmingCharacters(in: .whitespaces)
            } else if title.hasPrefix("Error:") {
                title = String(title.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces)
                severity = .error
            }

            let message = lines.dropFirst().joined(separator: "\n")
            var suggestedCommand: String?

            for line in lines {
                if line.hasPrefix("brew ") || line.hasPrefix("sudo ") || line.hasPrefix("export ") || line.hasPrefix("xcode-select ") || line.hasPrefix("rm ") || line.hasPrefix("chown ") || line.hasPrefix("git ") {
                    suggestedCommand = line
                    break
                }
            }

            var isAutoFixable = false
            var autoFixCommand: String?
            var requiresSudo = false
            var dryRunCommand: String?

            if let cmd = suggestedCommand {
                if cmd.hasPrefix("brew link ") || cmd.hasPrefix("brew tap ") || cmd.hasPrefix("brew cleanup") || cmd.hasPrefix("brew update") {
                    isAutoFixable = true
                    autoFixCommand = cmd
                    requiresSudo = false
                    if cmd.hasPrefix("brew link ") {
                        let target = cmd.replacingOccurrences(of: "brew link ", with: "")
                        dryRunCommand = "brew link --dry-run --overwrite \(target)"
                    } else if cmd.hasPrefix("brew cleanup") {
                        dryRunCommand = "brew cleanup -n"
                    }
                } else if cmd.hasPrefix("sudo ") {
                    requiresSudo = true
                }
            }

            // Heuristic domain & impact classification
            let combined = (title + " " + message).lowercased()
            let domain: DoctorFaultDomain
            let impact: String
            let fallout: String
            var safety: RemediationSafetyLevel = .requiresReview

            if combined.contains("unlinked kegs") || combined.contains("brew link") || combined.contains("not linked") {
                domain = .linkage
                impact = "Packages are stored in the Cellar but their executables are not linked to your system PATH."
                fallout = "Commands provided by these packages cannot be run in Terminal or by other tools."
                safety = .safeToAutoFix
                if autoFixCommand == nil, let pkg = extractPackageNameFromLinkMessage(message) {
                    isAutoFixable = true
                    autoFixCommand = "brew link --overwrite \(pkg)"
                    dryRunCommand = "brew link --dry-run --overwrite \(pkg)"
                }
            } else if combined.contains("broken symlink") || combined.contains("broken symlinks") || combined.contains("dangling symlink") {
                domain = .brokenSymlinks
                impact = "Symlinks point to nonexistent files from uninstalled or upgraded packages."
                fallout = "Path searches and library resolution may encounter dead references."
                safety = .safeToAutoFix
                isAutoFixable = true
                autoFixCommand = "brew cleanup -s"
                dryRunCommand = "brew cleanup -s -n"
            } else if combined.contains("shallow clone") || combined.contains("shallow") {
                domain = .shallowClone
                impact = "A Homebrew tap repository has shallow git history, preventing git branch operations and formula history lookups."
                fallout = "Certain tap updates or older formula revisions cannot be checked out."
                safety = .safeToAutoFix
                if autoFixCommand == nil {
                    isAutoFixable = true
                    autoFixCommand = "brew update-reset"
                    dryRunCommand = nil
                }
            } else if combined.contains("permission") || combined.contains("writable") || combined.contains("chown") || combined.contains("chmod") {
                domain = .permissions
                impact = "Homebrew paths have mismatched user or group permissions."
                fallout = "Package installations, upgrades, and uninstalls will fail with permission errors."
                safety = requiresSudo ? .manualIntervention : .requiresReview
            } else if combined.contains("xcode") || combined.contains("clt") || combined.contains("command line tools") {
                domain = .developerTools
                impact = "Apple Command Line Tools or Xcode are missing, outdated, or misconfigured."
                fallout = "Compiling formulae from source and native dependency linking will fail."
                safety = .manualIntervention
            } else if combined.contains("cleanup") || combined.contains("cache") || combined.contains("prune") {
                domain = .cacheBuildup
                impact = "Historical download bottles, build logs, and temporary caches are occupying disk space."
                fallout = "Unnecessary storage consumption and slower file operations."
                safety = .safeToAutoFix
                isAutoFixable = true
                autoFixCommand = "brew cleanup --prune=all"
                dryRunCommand = "brew cleanup -n"
            } else if combined.contains("missing") || combined.contains("dependency") {
                domain = .missingDeps
                impact = "Installed software is referencing library dependencies that are absent."
                fallout = "Applications and CLI utilities may crash when dynamic libraries cannot be loaded."
                safety = .requiresReview
            } else if combined.contains("git") || combined.contains("remote") || combined.contains("origin") {
                domain = .gitRepository
                impact = "A Homebrew tap git remote is out of sync or referencing an invalid upstream."
                fallout = "Formula updates and tap synchronization will fail to pull updates."
                safety = .requiresReview
            } else {
                domain = .general
                impact = "Homebrew configuration check identified an irregularity."
                fallout = "May impact Homebrew stability or formula compatibility."
                safety = isAutoFixable ? .safeToAutoFix : .requiresReview
            }

            diagnostics.append(
                BrewStoreDoctorDiagnostic(
                    id: "diag-\(index)",
                    severity: severity,
                    title: title.isEmpty ? "Configuration Notice" : title,
                    message: message.isEmpty ? title : message,
                    suggestedCommand: suggestedCommand,
                    isAutoFixable: isAutoFixable,
                    autoFixCommand: autoFixCommand,
                    requiresSudo: requiresSudo,
                    faultDomain: domain,
                    impactExplanation: impact,
                    potentialFallout: fallout,
                    safetyLevel: safety,
                    dryRunCommand: dryRunCommand
                )
            )
        }

        return diagnostics
    }

    private static func extractPackageNameFromLinkMessage(_ message: String) -> String? {
        let pattern = #"(?:brew link|brew link --overwrite)\s+([a-zA-Z0-9_\-\@\/\.]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = message as NSString
            if let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }
}
