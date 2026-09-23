import Foundation

struct ListeningPortEntry: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let port: Int
    let protocolType: String
    let processName: String
    let pid: Int
    let user: String
    let bindAddress: String
    let associatedHomebrewService: String?
    let hasConflict: Bool
    let conflictDescription: String?

    var displayAddress: String {
        bindAddress == "*" ? "All Interfaces (0.0.0.0)" : bindAddress
    }
}

@MainActor
final class ServicePortMatrixManager: ObservableObject {
    static let shared = ServicePortMatrixManager()

    @Published var entries: [ListeningPortEntry] = []
    @Published var isScanning = false
    @Published var conflictCount = 0
    @Published var statusMessage = "Ready to scan listening ports."

    nonisolated static let defaultPortMapping: [Int: [String]] = [
        5432: ["postgresql", "postgresql@14", "postgresql@15", "postgresql@16"],
        6379: ["redis", "redis-stack"],
        3306: ["mysql", "mysql@8.0", "mariadb"],
        80: ["nginx", "httpd"],
        8080: ["nginx", "caddy", "tomcat"],
        2019: ["caddy"],
        27017: ["mongodb-community"],
        5672: ["rabbitmq"],
        11211: ["memcached"],
        8086: ["influxdb"],
        9000: ["minio", "php"],
        11434: ["ollama"]
    ]

    /// Scans active TCP listening ports and correlates them with Homebrew service states.
    @discardableResult
    func scanPorts(services: [BrewStoreService] = []) async -> [ListeningPortEntry] {
        isScanning = true
        statusMessage = "Scanning open sockets and listening daemons…"

        let scannedEntries = await Task.detached(priority: .userInitiated) { () -> [ListeningPortEntry] in
            let result = BrewStoreCommandExecutor.shared.run(
                executablePath: "/usr/sbin/lsof",
                arguments: ["-iTCP", "-sTCP:LISTEN", "-n", "-P"],
                timeout: 8,
                category: .readOnly
            )

            guard result.succeeded || !result.standardOutput.isEmpty else {
                return []
            }

            return Self.parseLsofOutput(result.standardOutput, services: services)
        }.value

        self.entries = scannedEntries
        self.conflictCount = scannedEntries.filter(\.hasConflict).count
        self.isScanning = false
        self.statusMessage = "Found \(scannedEntries.count) listening sockets (\(conflictCount) conflicts detected)."
        return scannedEntries
    }

    /// Terminates a process occupying a disputed port after user confirmation.
    func terminateProcess(pid: Int) {
        guard pid > 100 else { return } // Safety guard against killing critical system daemons
        Task.detached(priority: .userInitiated) {
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: "/bin/kill",
                arguments: ["-15", "\(pid)"],
                timeout: 5,
                category: .reversibleMutation
            )

            await MainActor.run { [weak self] in
                self?.statusMessage = "Sent termination signal to PID \(pid)."
            }
        }
    }

    /// Parses raw `lsof` stdout into typed `ListeningPortEntry` structures.
    nonisolated static func parseLsofOutput(_ output: String, services: [BrewStoreService]) -> [ListeningPortEntry] {
        var results: [ListeningPortEntry] = []
        let lines = output.components(separatedBy: .newlines)

        let stoppedServiceNames = Set(services.filter { !$0.isRunning }.map { $0.name.lowercased() })

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            // Expected: COMMAND, PID, USER, FD, TYPE, DEVICE, SIZE/OFF, NODE, NAME
            guard parts.count >= 9 else { continue }
            if parts[0] == "COMMAND" { continue } // Header line

            let processName = String(parts[0])
            guard let pid = Int(parts[1]) else { continue }
            let user = String(parts[2])
            let type = String(parts[4])

            // Parse port from NAME (e.g. "*:5432" or "127.0.0.1:6379" or "[::1]:8080")
            let nameField = String(parts[8])
            guard let colonIndex = nameField.lastIndex(of: ":") else { continue }
            let portStr = nameField[nameField.index(after: colonIndex)...]
            guard let port = Int(portStr) else { continue }
            let bindAddr = String(nameField[..<colonIndex])

            // Determine associated Homebrew service
            let matchingServices = defaultPortMapping[port] ?? []
            let brewServiceName = matchingServices.first

            // Conflict detection:
            // Conflict if this port is claimed by a process whose name doesn't match the Homebrew service,
            // while that Homebrew service is configured in the system.
            var hasConflict = false
            var conflictDesc: String?

            if let brewServiceName {
                let procLower = processName.lowercased()
                let matchesExpectedService = matchingServices.contains { procLower.contains($0) }

                if !matchesExpectedService && stoppedServiceNames.contains(brewServiceName) {
                    hasConflict = true
                    conflictDesc = "Port \(port) is occupied by '\(processName)' (PID \(pid)), preventing Homebrew '\(brewServiceName)' from starting."
                }
            }

            // Deduplicate same port + pid (e.g. IPv4 + IPv6 on same process)
            let entryID = "\(port)_\(pid)_\(type)"
            if !results.contains(where: { $0.port == port && $0.pid == pid }) {
                results.append(ListeningPortEntry(
                    id: entryID,
                    port: port,
                    protocolType: type,
                    processName: processName,
                    pid: pid,
                    user: user,
                    bindAddress: bindAddr,
                    associatedHomebrewService: brewServiceName,
                    hasConflict: hasConflict,
                    conflictDescription: conflictDesc
                ))
            }
        }

        return results.sorted { $0.port < $1.port }
    }
}
