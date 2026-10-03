import Foundation
import SwiftUI
import Combine

enum ServiceCrashIssueType: String, Identifiable, CaseIterable, Codable, Sendable {
    case stalePIDLock = "Stale PID Lock File"
    case portConflict = "Port Conflict / Address In Use"
    case permissionDenied = "Permission Denied"
    case configurationSyntaxError = "Configuration Syntax Error"
    case uninitializedDataDirectory = "Uninitialized Data Directory"
    case resourceExhaustion = "Resource Exhaustion / Limits"
    case unknownCrash = "Uncategorized Crash"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .stalePIDLock: return "lock.slash.fill"
        case .portConflict: return "network.slash"
        case .permissionDenied: return "hand.raised.fill"
        case .configurationSyntaxError: return "doc.badge.ellipsis"
        case .uninitializedDataDirectory: return "folder.badge.gearshape"
        case .resourceExhaustion: return "gauge.with.needle.fill"
        case .unknownCrash: return "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .stalePIDLock: return .orange
        case .portConflict: return .red
        case .permissionDenied: return .purple
        case .configurationSyntaxError: return .yellow
        case .uninitializedDataDirectory: return .blue
        case .resourceExhaustion: return .pink
        case .unknownCrash: return .secondary
        }
    }
}

enum RemediationActionType: Hashable, Sendable {
    case deleteFile(path: String)
    case killProcess(pid: Int, processName: String)
    case fixDirectoryPermissions(path: String)
    case restartService
    case openFileInEditor(path: String, line: Int?)
    case openPortMatrix
}

struct ServiceCrashRemediationAction: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let actionType: RemediationActionType
    let isRecommended: Bool
    let isAutomated: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        actionType: RemediationActionType,
        isRecommended: Bool = false,
        isAutomated: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.actionType = actionType
        self.isRecommended = isRecommended
        self.isAutomated = isAutomated
    }
}

struct ServiceCrashDiagnosis: Identifiable, Hashable, Sendable {
    var id: String { serviceName }
    let serviceName: String
    let issueType: ServiceCrashIssueType
    let headline: String
    let explanation: String
    let matchedLogExcerpt: String
    let logFilePath: String?
    let remediations: [ServiceCrashRemediationAction]
    let timestamp: Date
    let affectedPort: Int?
    let affectedFilePath: String?
}

@MainActor
final class ServiceCrashDiagnostician: ObservableObject {
    static let shared = ServiceCrashDiagnostician()

    @Published private(set) var diagnoses: [String: ServiceCrashDiagnosis] = [:]
    @Published private(set) var isDiagnosing: [String: Bool] = [:]
    @Published private(set) var isRemediating: [String: Bool] = [:]
    @Published private(set) var remediationStatus: [String: String] = [:]

    private let fileManager = FileManager.default
    private let commandExecutor: BrewStoreCommandExecutor

    init(commandExecutor: BrewStoreCommandExecutor = .shared) {
        self.commandExecutor = commandExecutor
    }

    func diagnosis(for serviceName: String) -> ServiceCrashDiagnosis? {
        diagnoses[serviceName]
    }

    /// Run deep crash analysis for a given service.
    @discardableResult
    func diagnoseCrash(for service: BrewStoreService, brewPrefix: String? = nil) async -> ServiceCrashDiagnosis? {
        isDiagnosing[service.name] = true
        defer { isDiagnosing[service.name] = false }

        let prefix = brewPrefix ?? (fileManager.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")
        let logFiles = BrewStoreServiceLogManager.candidateLogPaths(for: service.name, prefix: prefix)

        // Read log contents
        var combinedLogLines: [String] = []
        var detectedLogPath: String?

        for path in logFiles {
            if fileManager.fileExists(atPath: path),
               let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                detectedLogPath = path
                let lines = contents.components(separatedBy: .newlines).suffix(150)
                combinedLogLines.append(contentsOf: lines)
                break
            }
        }

        let diagnosis = await analyzeServiceState(
            service: service,
            logLines: combinedLogLines,
            logFilePath: detectedLogPath,
            prefix: prefix
        )

        if let diagnosis {
            self.diagnoses[service.name] = diagnosis
        }
        return diagnosis
    }

    func diagnoseAllErroredServices(services: [BrewStoreService], brewPrefix: String? = nil) async {
        let errored = services.filter(\.isError)
        await withTaskGroup(of: Void.self) { group in
            for svc in errored {
                group.addTask { @MainActor in
                    _ = await self.diagnoseCrash(for: svc, brewPrefix: brewPrefix)
                }
            }
        }
    }

    // MARK: - Pattern Analysis Engine

    nonisolated func analyzeServiceState(
        service: BrewStoreService,
        logLines: [String],
        logFilePath: String?,
        prefix: String
    ) async -> ServiceCrashDiagnosis? {
        let reversedLines = Array(logLines.reversed())
        let fullLogText = logLines.joined(separator: "\n")

        // 1. Check for Stale PID File
        if let stalePID = checkForStalePID(service: service, logText: fullLogText, prefix: prefix) {
            return stalePID
        }

        // 2. Check for Port Conflict / Address in Use
        if let portConflict = await checkForPortConflict(service: service, logLines: reversedLines, prefix: prefix) {
            return portConflict
        }

        // 3. Check for Permission Denied
        if let permIssue = checkForPermissionDenied(service: service, logLines: reversedLines, logFilePath: logFilePath) {
            return permIssue
        }

        // 4. Check for Configuration Syntax Error
        if let configIssue = checkForConfigError(service: service, logLines: reversedLines, prefix: prefix) {
            return configIssue
        }

        // 5. Check for Uninitialized Data Directory
        if let uninitIssue = checkForUninitializedData(service: service, logLines: reversedLines, prefix: prefix) {
            return uninitIssue
        }

        // 6. Check for Resource Exhaustion
        if let resourceIssue = checkForResourceExhaustion(service: service, logLines: reversedLines) {
            return resourceIssue
        }

        // 7. Generic Fallback if error status but no known pattern
        if service.isError {
            let lastFewLines = logLines.suffix(3).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return ServiceCrashDiagnosis(
                serviceName: service.name,
                issueType: .unknownCrash,
                headline: "Unexpected Exit Code (\(service.status))",
                explanation: "The daemon process terminated with an error code. Check the log output for recent panic or exit messages.",
                matchedLogExcerpt: lastFewLines.isEmpty ? "No recent log entries detected." : lastFewLines,
                logFilePath: logFilePath,
                remediations: [
                    ServiceCrashRemediationAction(
                        title: "Attempt Service Restart",
                        subtitle: "Gracefully restart '\(service.name)' to attempt recovery.",
                        actionType: .restartService,
                        isRecommended: true
                    )
                ],
                timestamp: Date(),
                affectedPort: nil,
                affectedFilePath: logFilePath
            )
        }

        return nil
    }

    // MARK: - Specialized Detection Heuristics

    private nonisolated func checkForStalePID(
        service: BrewStoreService,
        logText: String,
        prefix: String
    ) -> ServiceCrashDiagnosis? {
        let fm = FileManager.default
        let name = service.name.lowercased()

        var candidatePIDPaths: [String] = []

        if name.contains("postgres") {
            candidatePIDPaths = [
                "\(prefix)/var/postgres/postmaster.pid",
                "\(prefix)/var/postgresql/postmaster.pid",
                "\(prefix)/var/data/postmaster.pid"
            ]
            // Also check versioned postgres: /var/postgresql@*
            if let varContents = try? fm.contentsOfDirectory(atPath: "\(prefix)/var") {
                for item in varContents where item.hasPrefix("postgresql@") || item.hasPrefix("postgresql-") {
                    candidatePIDPaths.append("\(prefix)/var/\(item)/postmaster.pid")
                }
            }
        } else if name.contains("nginx") {
            candidatePIDPaths = [
                "\(prefix)/var/run/nginx.pid",
                "\(prefix)/var/run/nginx/nginx.pid"
            ]
        } else if name.contains("mysql") || name.contains("mariadb") {
            candidatePIDPaths = [
                "\(prefix)/var/mysql/mysqld.pid",
                "\(prefix)/var/mysql/\(Host.current().localizedName ?? "localhost").pid"
            ]
        } else if name.contains("redis") {
            candidatePIDPaths = [
                "\(prefix)/var/run/redis.pid",
                "\(prefix)/var/run/redis/redis.pid"
            ]
        }

        var foundStalePath: String?
        for path in candidatePIDPaths {
            if fm.fileExists(atPath: path) {
                // Read PID from file
                if let pidString = try? String(contentsOfFile: path, encoding: .utf8),
                   let firstLine = pidString.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces),
                   let pid = Int32(firstLine) {
                    // Check if PID is alive
                    if kill(pid, 0) != 0 && errno == ESRCH {
                        foundStalePath = path
                        break
                    }
                } else {
                    // PID file exists but is empty or unreadable
                    foundStalePath = path
                    break
                }
            }
        }

        let hasPIDLogMention = logText.localizedCaseInsensitiveContains("postmaster.pid already exists") ||
            logText.localizedCaseInsensitiveContains("lock file \"postmaster.pid\" already exists") ||
            logText.localizedCaseInsensitiveContains("The server quit without updating PID file") ||
            logText.localizedCaseInsensitiveContains("nginx.pid\" failed")

        let stalePath = foundStalePath ?? candidatePIDPaths.first(where: { fm.fileExists(atPath: $0) }) ?? (hasPIDLogMention ? (candidatePIDPaths.first ?? "\(prefix)/var/run/\(service.name).pid") : nil)

        if hasPIDLogMention || foundStalePath != nil, let resolvedPath = stalePath {
            return ServiceCrashDiagnosis(
                serviceName: service.name,
                issueType: .stalePIDLock,
                headline: "Stale PID Lock File Detected",
                explanation: "The daemon failed to boot because a leftover process lock file ('\(URL(fileURLWithPath: resolvedPath).lastPathComponent)') still exists from a previous crash. The process holding the lock is no longer active.",
                matchedLogExcerpt: "Found orphaned lock file at: \(resolvedPath)",
                logFilePath: nil,
                remediations: [
                    ServiceCrashRemediationAction(
                        title: "Clear Stale PID File & Restart",
                        subtitle: "Safely delete '\(URL(fileURLWithPath: resolvedPath).lastPathComponent)' and relaunch \(service.name).",
                        actionType: .deleteFile(path: resolvedPath),
                        isRecommended: true,
                        isAutomated: true
                    )
                ],
                timestamp: Date(),
                affectedPort: nil,
                affectedFilePath: resolvedPath
            )
        }

        return nil
    }

    private nonisolated func checkForPortConflict(
        service: BrewStoreService,
        logLines: [String],
        prefix: String
    ) async -> ServiceCrashDiagnosis? {
        let conflictKeywords = [
            "address already in use",
            "bind: address already in use",
            "could not create server tcp listening socket",
            "bind on tcp/ip port: address already in use",
            "failed (48: address already in use)"
        ]

        var matchedLine: String?
        for line in logLines {
            let lower = line.lowercased()
            if conflictKeywords.contains(where: { lower.contains($0) }) {
                matchedLine = line
                break
            }
        }

        // Determine port associated with service
        let serviceName = service.name.lowercased()
        var expectedPort: Int?
        for (port, names) in ServicePortMatrixManager.defaultPortMapping {
            if names.contains(where: { serviceName.contains($0) }) {
                expectedPort = port
                break
            }
        }

        // If log matched or known port is blocked
        if matchedLine != nil || expectedPort != nil {
            // Check lsof to find who owns the port
            if let port = expectedPort {
                let lsofResult = BrewStoreCommandExecutor.shared.run(
                    executablePath: "/usr/sbin/lsof",
                    arguments: ["-iTCP:\(port)", "-sTCP:LISTEN", "-n", "-P"],
                    timeout: 5,
                    category: .readOnly
                )

                if lsofResult.succeeded && !lsofResult.standardOutput.isEmpty {
                    let lines = lsofResult.standardOutput.components(separatedBy: .newlines)
                    for line in lines where !line.hasPrefix("COMMAND") && !line.isEmpty {
                        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                        if parts.count >= 2, let pid = Int(parts[1]) {
                            let rogueName = String(parts[0])

                            return ServiceCrashDiagnosis(
                                serviceName: service.name,
                                issueType: .portConflict,
                                headline: "Port \(port) Occupied by '\(rogueName)' (PID \(pid))",
                                explanation: "Homebrew daemon '\(service.name)' failed to bind to port \(port) because another process ('\(rogueName)') is actively listening on this socket.",
                                matchedLogExcerpt: matchedLine ?? line,
                                logFilePath: nil,
                                remediations: [
                                    ServiceCrashRemediationAction(
                                        title: "Terminate Conflicting Process (\(rogueName))",
                                        subtitle: "Send SIGTERM to PID \(pid) on port \(port) and restart \(service.name).",
                                        actionType: .killProcess(pid: pid, processName: rogueName),
                                        isRecommended: true,
                                        isAutomated: true
                                    ),
                                    ServiceCrashRemediationAction(
                                        title: "Open Service Port Matrix",
                                        subtitle: "Inspect all open sockets and listening daemons.",
                                        actionType: .openPortMatrix,
                                        isRecommended: false,
                                        isAutomated: false
                                    )
                                ],
                                timestamp: Date(),
                                affectedPort: port,
                                affectedFilePath: nil
                            )
                        }
                    }
                }
            }

            if let matchedLine {
                return ServiceCrashDiagnosis(
                    serviceName: service.name,
                    issueType: .portConflict,
                    headline: "Socket Bind Conflict Detected",
                    explanation: "Service reported that its target listening port is already bound by another process.",
                    matchedLogExcerpt: matchedLine,
                    logFilePath: nil,
                    remediations: [
                        ServiceCrashRemediationAction(
                            title: "Open Service Port Matrix",
                            subtitle: "Identify which application is currently occupying the port.",
                            actionType: .openPortMatrix,
                            isRecommended: true,
                            isAutomated: false
                        )
                    ],
                    timestamp: Date(),
                    affectedPort: expectedPort,
                    affectedFilePath: nil
                )
            }
        }

        return nil
    }

    private nonisolated func checkForPermissionDenied(
        service: BrewStoreService,
        logLines: [String],
        logFilePath: String?
    ) -> ServiceCrashDiagnosis? {
        let permKeywords = [
            "permission denied",
            "access denied for user",
            "failed to open log file",
            "could not open file",
            "operation not permitted"
        ]

        for line in logLines {
            let lower = line.lowercased()
            if permKeywords.contains(where: { lower.contains($0) }) {
                // Try extracting path between quotes or after keywords
                var targetPath = logFilePath
                if let quoteStart = line.range(of: "\""),
                   let quoteEnd = line.range(of: "\"", range: quoteStart.upperBound..<line.endIndex) {
                    targetPath = String(line[quoteStart.upperBound..<quoteEnd.lowerBound])
                }

                return ServiceCrashDiagnosis(
                    serviceName: service.name,
                    issueType: .permissionDenied,
                    headline: "File System Permission Denied",
                    explanation: "The daemon process could not access necessary log, data, or configuration files due to restrictive file permissions.",
                    matchedLogExcerpt: line,
                    logFilePath: logFilePath,
                    remediations: [
                        ServiceCrashRemediationAction(
                            title: "Repair Directory & File Permissions",
                            subtitle: "Grant read/write permissions for current user on '\(targetPath ?? "target path")'.",
                            actionType: .fixDirectoryPermissions(path: targetPath ?? logFilePath ?? ""),
                            isRecommended: true,
                            isAutomated: true
                        )
                    ],
                    timestamp: Date(),
                    affectedPort: nil,
                    affectedFilePath: targetPath
                )
            }
        }
        return nil
    }

    private nonisolated func checkForConfigError(
        service: BrewStoreService,
        logLines: [String],
        prefix: String
    ) -> ServiceCrashDiagnosis? {
        let configKeywords = [
            "syntax error",
            "unknown directive",
            "invalid parameter",
            "configuration error",
            "failed to parse config",
            "[emerg]"
        ]

        for line in logLines {
            let lower = line.lowercased()
            if configKeywords.contains(where: { lower.contains($0) }) {
                var configPath = "\(prefix)/etc/\(service.name)/\(service.name).conf"
                var lineNumber: Int?

                // Match syntax like "... in /opt/homebrew/etc/nginx/nginx.conf:42"
                if let inRange = line.range(of: " in ") {
                    let afterIn = line[inRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    let token = afterIn.split(separator: " ").first ?? ""
                    let parts = token.split(separator: ":")
                    if let firstPart = parts.first, firstPart.hasPrefix("/") {
                        configPath = String(firstPart)
                    }
                    if parts.count >= 2, let parsed = Int(parts[1]) {
                        lineNumber = parsed
                    }
                }

                if lineNumber == nil, let lastColon = line.lastIndex(of: ":") {
                    let suffix = line[line.index(after: lastColon)...].trimmingCharacters(in: .whitespaces)
                    if let firstWord = suffix.split(separator: " ").first, let parsed = Int(firstWord) {
                        lineNumber = parsed
                    }
                }

                return ServiceCrashDiagnosis(
                    serviceName: service.name,
                    issueType: .configurationSyntaxError,
                    headline: "Configuration Directive Syntax Error",
                    explanation: "The service configuration file contains an unrecognized or invalid directive that prevented startup.",
                    matchedLogExcerpt: line,
                    logFilePath: nil,
                    remediations: [
                        ServiceCrashRemediationAction(
                            title: "Open Configuration File",
                            subtitle: "Open '\(URL(fileURLWithPath: configPath).lastPathComponent)'\(lineNumber.map { " at line \($0)" } ?? "") to review syntax.",
                            actionType: .openFileInEditor(path: configPath, line: lineNumber),
                            isRecommended: true,
                            isAutomated: false
                        )
                    ],
                    timestamp: Date(),
                    affectedPort: nil,
                    affectedFilePath: configPath
                )
            }
        }
        return nil
    }

    private nonisolated func checkForUninitializedData(
        service: BrewStoreService,
        logLines: [String],
        prefix: String
    ) -> ServiceCrashDiagnosis? {
        let uninitKeywords = [
            "database cluster has not been initialized",
            "directory does not exist",
            "no such file or directory",
            "table 'mysql.user' doesn't exist"
        ]

        for line in logLines {
            let lower = line.lowercased()
            if uninitKeywords.contains(where: { lower.contains($0) }) {
                return ServiceCrashDiagnosis(
                    serviceName: service.name,
                    issueType: .uninitializedDataDirectory,
                    headline: "Uninitialized Service Data Store",
                    explanation: "The database or server instance has not initialized its base storage cluster or data directory.",
                    matchedLogExcerpt: line,
                    logFilePath: nil,
                    remediations: [
                        ServiceCrashRemediationAction(
                            title: "Attempt Service Restart",
                            subtitle: "Restart the service after initializing storage.",
                            actionType: .restartService,
                            isRecommended: true,
                            isAutomated: true
                        )
                    ],
                    timestamp: Date(),
                    affectedPort: nil,
                    affectedFilePath: nil
                )
            }
        }
        return nil
    }

    private nonisolated func checkForResourceExhaustion(
        service: BrewStoreService,
        logLines: [String]
    ) -> ServiceCrashDiagnosis? {
        let resourceKeywords = [
            "cannot allocate memory",
            "out of memory",
            "too many open files",
            "max open files exceeded"
        ]

        for line in logLines {
            let lower = line.lowercased()
            if resourceKeywords.contains(where: { lower.contains($0) }) {
                return ServiceCrashDiagnosis(
                    serviceName: service.name,
                    issueType: .resourceExhaustion,
                    headline: "Resource Limit Reached",
                    explanation: "The daemon exceeded system limits such as maximum open file descriptors (nofile) or available memory.",
                    matchedLogExcerpt: line,
                    logFilePath: nil,
                    remediations: [
                        ServiceCrashRemediationAction(
                            title: "Restart Service",
                            subtitle: "Restart the daemon to reclaim system handles.",
                            actionType: .restartService,
                            isRecommended: true,
                            isAutomated: true
                        )
                    ],
                    timestamp: Date(),
                    affectedPort: nil,
                    affectedFilePath: nil
                )
            }
        }
        return nil
    }

    // MARK: - Remediation Execution

    func executeRemediation(
        _ remediation: ServiceCrashRemediationAction,
        for service: BrewStoreService,
        manager: HomebrewManager
    ) async throws {
        isRemediating[service.name] = true
        remediationStatus[service.name] = "Applying '\(remediation.title)'…"
        defer {
            isRemediating[service.name] = false
            remediationStatus[service.name] = nil
        }

        switch remediation.actionType {
        case let .deleteFile(path):
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
            manager.perform(service: service, action: .restart)

        case let .killProcess(pid, _):
            ServicePortMatrixManager.shared.terminateProcess(pid: pid)
            try? await Task.sleep(nanoseconds: 500_000_000)
            manager.perform(service: service, action: .restart)

        case let .fixDirectoryPermissions(path):
            if !path.isEmpty && fileManager.fileExists(atPath: path) {
                // Add write permissions for user: chmod u+rw
                _ = commandExecutor.run(
                    executablePath: "/bin/chmod",
                    arguments: ["-R", "u+rw", path],
                    timeout: 10,
                    category: .reversibleMutation
                )
            }
            manager.perform(service: service, action: .restart)

        case .restartService:
            manager.perform(service: service, action: .restart)

        case let .openFileInEditor(path, _):
            if fileManager.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }

        case .openPortMatrix:
            // Handled via UI trigger
            break
        }

        // Wait brief interval and re-diagnose
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        _ = await diagnoseCrash(for: service, brewPrefix: manager.brewPrefix)
    }
}
