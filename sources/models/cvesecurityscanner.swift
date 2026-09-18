import Foundation

enum CVESeverity: String, Codable, Comparable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case info = "Info"

    var badgeColor: String {
        switch self {
        case .critical: "red"
        case .high: "orange"
        case .medium: "yellow"
        case .info: "blue"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .critical: 0
        case .high: 1
        case .medium: 2
        case .info: 3
        }
    }

    static func < (lhs: CVESeverity, rhs: CVESeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

struct CVESecurityIssue: Identifiable, Hashable, Codable {
    let id: String
    let packageName: String
    let packageKind: BrewPackageKind
    let title: String
    let description: String
    let severity: CVESeverity
    let remediationAction: String
    let cveIdentifier: String?
}

struct CVESecurityReport: Hashable, Codable {
    let timestamp: Date
    let totalChecked: Int
    let issues: [CVESecurityIssue]
    let securityScore: Int

    var criticalIssues: [CVESecurityIssue] {
        issues.filter { $0.severity == .critical }
    }

    var highIssues: [CVESecurityIssue] {
        issues.filter { $0.severity == .high }
    }

    var mediumIssues: [CVESecurityIssue] {
        issues.filter { $0.severity == .medium }
    }

    var isClean: Bool {
        issues.isEmpty
    }
}

enum CVEScanError: Error, LocalizedError, Equatable, Sendable {
    case timeout(seconds: Int)
    case cancelled
    case commandFailed(exitCode: Int32?, message: String)
    case retryable(reason: String, isLockError: Bool)
    case homebrewUnavailable
    case malformedOutput(details: String)

    var errorDescription: String? {
        switch self {
        case let .timeout(seconds):
            return "Security audit timed out after \(seconds)s."
        case .cancelled:
            return "Security audit was cancelled."
        case let .commandFailed(exitCode, message):
            if let code = exitCode {
                return "Security audit command failed (exit code \(code)): \(message)"
            }
            return "Security audit command failed: \(message)"
        case let .retryable(reason, _):
            return "Temporary scan issue: \(reason)"
        case .homebrewUnavailable:
            return "Homebrew executable path is unavailable on this system."
        case let .malformedOutput(details):
            return "Malformed Homebrew audit output: \(details)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .timeout:
            return "The audit took longer than expected. Check if Homebrew is waiting for network responses or retry the scan."
        case .cancelled:
            return "You can restart the security audit whenever you are ready."
        case let .retryable(_, isLockError):
            if isLockError {
                return "Another Homebrew process holds the lockfile. Wait for other operations to finish, then retry."
            }
            return "This appears to be a transient issue. Try running the security audit again."
        case .commandFailed:
            return "Run Homebrew Doctor from Settings to diagnose repository and environment issues."
        case .homebrewUnavailable:
            return "Ensure Homebrew is installed and configured in Settings."
        case .malformedOutput:
            return "Check Homebrew health with 'brew doctor' or update Homebrew definitions."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .timeout, .retryable, .cancelled:
            true
        case .commandFailed, .homebrewUnavailable, .malformedOutput:
            true
        }
    }
}

enum CVEScanState: Equatable {
    case idle
    case scanning(startedAt: Date)
    case succeeded(CVESecurityReport)
    case failed(CVEScanError)
}

@MainActor
final class BrewStoreCVESecurityScanner: ObservableObject {
    static let shared = BrewStoreCVESecurityScanner()

    @Published var report: CVESecurityReport?
    @Published var isScanning = false
    @Published var scanError: CVEScanError?
    @Published var scanState: CVEScanState = .idle
    @Published var lastScanDate: Date?

    typealias CommandRunner = @Sendable (
        _ executablePath: String,
        _ arguments: [String],
        _ timeout: TimeInterval,
        _ cancellationCheck: (@Sendable () -> Bool)?
    ) -> BrewStoreCommandResult

    private let commandRunner: CommandRunner
    private var activeTask: Task<Void, Never>?
    private var cancellationState: BrewStoreCancellationState?

    init(commandRunner: CommandRunner? = nil) {
        self.commandRunner = commandRunner ?? { execPath, args, timeout, cancelCheck in
            BrewStoreCommandExecutor.shared.run(
                executablePath: execPath,
                arguments: args,
                timeout: timeout,
                category: .readOnly,
                maximumOutputBytes: 2_000_000,
                cancellationCheck: cancelCheck
            )
        }
    }

    func cancelScan() {
        cancellationState?.cancel()
        activeTask?.cancel()
        activeTask = nil
        isScanning = false
        scanError = .cancelled
        scanState = .failed(.cancelled)
    }

    func scanSecurity(manager: HomebrewManager, timeout: TimeInterval = 15) {
        guard let brewPath = manager.brewPath, !brewPath.isEmpty else {
            self.isScanning = false
            self.scanError = .homebrewUnavailable
            self.scanState = .failed(.homebrewUnavailable)
            return
        }

        // Cancel any prior in-flight scan
        activeTask?.cancel()
        cancellationState?.cancel()

        let cancelToken = BrewStoreCancellationState()
        self.cancellationState = cancelToken
        self.isScanning = true
        self.scanError = nil
        self.scanState = .scanning(startedAt: Date())

        let installed = manager.packages.filter(\.isInstalled)
        let runner = self.commandRunner

        self.activeTask = Task.detached(priority: .userInitiated) { [weak self, cancelToken] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isScanning = false
                }
            }

            if cancelToken.isCancelled || Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.scanError = .cancelled
                    self?.scanState = .failed(.cancelled)
                }
                return
            }

            let res = runner(
                brewPath,
                ["audit", "--installed"],
                timeout,
                { cancelToken.isCancelled || Task.isCancelled }
            )

            if res.wasCancelled || cancelToken.isCancelled || Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.scanError = .cancelled
                    self?.scanState = .failed(.cancelled)
                }
                return
            }

            if res.didTimeOut {
                await MainActor.run { [weak self] in
                    let err = CVEScanError.timeout(seconds: Int(timeout))
                    self?.scanError = err
                    self?.scanState = .failed(err)
                }
                return
            }

            if let launchErr = res.launchErrorDescription {
                await MainActor.run { [weak self] in
                    let err = CVEScanError.commandFailed(exitCode: nil, message: launchErr)
                    self?.scanError = err
                    self?.scanState = .failed(err)
                }
                return
            }

            let rawOutput = res.standardOutput + "\n" + res.standardError
            let lowerErr = res.standardError.lowercased()

            // Check for retryable lockfile errors
            if lowerErr.contains("another active homebrew process") ||
                lowerErr.contains("lockfile") ||
                lowerErr.contains("resource temporarily unavailable") ||
                lowerErr.contains("operation not permitted") {
                await MainActor.run { [weak self] in
                    let err = CVEScanError.retryable(reason: "Homebrew lock is held by another running operation.", isLockError: true)
                    self?.scanError = err
                    self?.scanState = .failed(err)
                }
                return
            }

            // Check for retryable network connectivity issues
            if lowerErr.contains("could not resolve host") ||
                lowerErr.contains("connection refused") ||
                lowerErr.contains("failed to connect") ||
                lowerErr.contains("ssl handshake") {
                await MainActor.run { [weak self] in
                    let err = CVEScanError.retryable(reason: "Network connection to Homebrew advisory source failed.", isLockError: false)
                    self?.scanError = err
                    self?.scanState = .failed(err)
                }
                return
            }

            // Fatal command failure check (exit status != 0 and != 1, with empty output or ruby crash)
            if let exitCode = res.terminationStatus, exitCode != 0, exitCode != 1 {
                if rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    lowerErr.contains("fatal:") ||
                    lowerErr.contains("error: undefined method") ||
                    lowerErr.contains("loaderror") {
                    let errMsg = res.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run { [weak self] in
                        let err = CVEScanError.commandFailed(exitCode: exitCode, message: errMsg.isEmpty ? "Process terminated with exit code \(exitCode)." : errMsg)
                        self?.scanError = err
                        self?.scanState = .failed(err)
                    }
                    return
                }
            }

            // Check for malformed output
            let validationResult = Self.validateAuditOutput(rawOutput)
            switch validationResult {
            case let .failure(err):
                await MainActor.run { [weak self] in
                    self?.scanError = err
                    self?.scanState = .failed(err)
                }
                return
            case .success:
                break
            }

            var issues = Self.parseAuditOutput(output: rawOutput, installedPackages: installed)

            // Merge curated high-impact advisories if audit was limited or offline
            for adv in BrewStoreCVEScanningManager.knownAdvisories {
                if let matchingPkg = installed.first(where: { $0.id.lowercased() == adv.packageID.lowercased() }) {
                    let isStillVulnerable = BrewStoreCVEScanningManager.isPackageVulnerable(package: matchingPkg, advisory: adv)
                    if isStillVulnerable, !issues.contains(where: { $0.cveIdentifier == adv.id }) {
                        let remediation: String = {
                            if adv.fixedVersion.lowercased().contains("upgrade to") {
                                return adv.fixedVersion
                            }
                            return "Upgrade \(adv.packageID) to \(adv.fixedVersion)"
                        }()
                        issues.append(CVESecurityIssue(
                            id: UUID().uuidString,
                            packageName: adv.packageID,
                            packageKind: .formula,
                            title: adv.title,
                            description: adv.title,
                            severity: adv.severity == .critical ? .critical : .high,
                            remediationAction: remediation,
                            cveIdentifier: adv.id
                        ))
                    }
                }
            }

            var score = 100
            for issue in issues {
                switch issue.severity {
                case .critical: score -= 25
                case .high: score -= 15
                case .medium: score -= 8
                case .info: score -= 3
                }
            }
            let finalScore = max(0, min(100, score))

            let rep = CVESecurityReport(
                timestamp: Date(),
                totalChecked: installed.count,
                issues: issues,
                securityScore: finalScore
            )

            await MainActor.run { [weak self] in
                self?.report = rep
                self?.scanError = nil
                self?.scanState = .succeeded(rep)
                self?.lastScanDate = Date()
            }
        }
    }

    nonisolated static func validateAuditOutput(_ output: String) -> Result<Void, CVEScanError> {
        if output.contains("\0") {
            return .failure(.malformedOutput(details: "Binary null byte (0x00) corruption detected in stream."))
        }

        let hasCorruptControl = output.unicodeScalars.contains { scalar in
            (scalar.value < 0x20 && scalar.value != 0x09 && scalar.value != 0x0A && scalar.value != 0x0D) || scalar.value == 0x7F
        }
        if hasCorruptControl {
            return .failure(.malformedOutput(details: "Illegal non-printable control characters detected in stream."))
        }

        return .success(())
    }

    nonisolated static func parseAuditOutput(output: String, installedPackages: [BrewStorePackage]) -> [CVESecurityIssue] {
        var issues: [CVESecurityIssue] = []
        let lines = output.components(separatedBy: .newlines)
        var currentPkg: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if !line.hasPrefix(" "), !line.hasPrefix("\t"), line.contains(":") {
                // Header line: e.g. "openssl@1.1: or node:"
                currentPkg = line.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            } else if let pkgName = currentPkg {
                let lower = trimmed.lowercased()
                let severity: CVESeverity
                var cve: String?

                if lower.contains("cve-") {
                    severity = .critical
                    if let range = lower.range(of: "cve-[0-9]{4}-[0-9]+", options: .regularExpression) {
                        cve = String(lower[range]).uppercased()
                    }
                } else if lower.contains("deprecated") || lower.contains("disabled") || lower.contains("security") {
                    severity = .high
                } else if lower.contains("warning") || lower.contains("insecure") {
                    severity = .medium
                } else {
                    severity = .info
                }

                let matched = installedPackages.first { $0.id.lowercased() == pkgName.lowercased() || $0.name.lowercased() == pkgName.lowercased() }
                let kind = matched?.kind ?? .formula

                issues.append(CVESecurityIssue(
                    id: "\(pkgName)-\(issues.count)",
                    packageName: pkgName,
                    packageKind: kind,
                    title: cve.map { "Security Advisory (\($0))" } ?? "Security Audit Notice",
                    description: trimmed,
                    severity: severity,
                    remediationAction: severity == .critical || severity == .high ? "Upgrade / Replace Package" : "Review Configuration",
                    cveIdentifier: cve
                ))
            }
        }

        // Also check if any installed package is marked deprecated or outdated
        for pkg in installedPackages where pkg.isOutdated {
            if !issues.contains(where: { $0.packageName == pkg.id }) {
                issues.append(CVESecurityIssue(
                    id: "\(pkg.id)-outdated",
                    packageName: pkg.name,
                    packageKind: pkg.kind,
                    title: "Pending Security / Version Upgrade",
                    description: "Package version \(pkg.installedVersion ?? "") is behind upstream \(pkg.version).",
                    severity: .info,
                    remediationAction: "Upgrade to v\(pkg.version)",
                    cveIdentifier: nil
                ))
            }
        }

        return issues.sorted { $0.severity < $1.severity }
    }
}
