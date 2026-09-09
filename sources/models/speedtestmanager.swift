import Combine
import Foundation

struct SpeedTestJSONResult: Decodable {
    struct ServerResult: Decodable {
        let name: String?
        let country: String?
        let latency: Double?
        let dl_speed: Double?
        let ul_speed: Double?
    }

    let timestamp: String?
    let servers: [ServerResult]?
}

@MainActor
final class BrewStoreSpeedTestManager: ObservableObject {
    static let shared = BrewStoreSpeedTestManager()

    private nonisolated static let speedLock = NSLock()
    private nonisolated(unsafe) static var _cachedSpeedMBps: Double?

    nonisolated static var cachedDownloadSpeedMBps: Double? {
        speedLock.lock()
        defer { speedLock.unlock() }
        return _cachedSpeedMBps
    }

    nonisolated static func setCachedSpeedMBps(_ val: Double?) {
        speedLock.lock()
        defer { speedLock.unlock() }
        _cachedSpeedMBps = val
    }

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    private enum Keys {
        static let periodicEnabled = "pref_speedtest_periodic_enabled"
        static let intervalSeconds = "pref_speedtest_interval_seconds"
        static let lastSpeedBytes = "pref_speedtest_last_speed_bytes"
        static let lastLatencyMs = "pref_speedtest_last_latency_ms"
        static let lastTimestamp = "pref_speedtest_last_timestamp"
    }

    @Published var isAvailable: Bool = false
    @Published var binaryPath: String?
    @Published var isRunningTest: Bool = false
    @Published var lastMeasuredSpeedBytesPerSec: Double? {
        didSet {
            if let speed = lastMeasuredSpeedBytesPerSec {
                defaults.set(speed, forKey: Keys.lastSpeedBytes)
                Self.setCachedSpeedMBps(speed > 0 ? (speed / 1_000_000.0) : nil)
            } else {
                Self.setCachedSpeedMBps(nil)
            }
        }
    }

    @Published var lastMeasuredLatencyMs: Double? {
        didSet {
            if let latency = lastMeasuredLatencyMs {
                defaults.set(latency, forKey: Keys.lastLatencyMs)
            }
        }
    }

    @Published var lastMeasuredAt: Date? {
        didSet {
            if let date = lastMeasuredAt {
                defaults.set(date.timeIntervalSince1970, forKey: Keys.lastTimestamp)
            }
        }
    }

    @Published var lastErrorMessage: String?

    @Published var isPeriodicEnabled: Bool {
        didSet {
            defaults.set(isPeriodicEnabled, forKey: Keys.periodicEnabled)
            rescheduleTimer()
        }
    }

    @Published var intervalSeconds: Int {
        didSet {
            let clamped = max(5, min(3600, intervalSeconds))
            if intervalSeconds != clamped {
                intervalSeconds = clamped
            }
            defaults.set(clamped, forKey: Keys.intervalSeconds)
            rescheduleTimer()
        }
    }

    var currentDownloadSpeedMBps: Double? {
        guard let bytesPerSec = lastMeasuredSpeedBytesPerSec, bytesPerSec > 0 else { return nil }
        return bytesPerSec / 1_000_000.0
    }

    var currentDownloadSpeedMbps: Double? {
        guard let bytesPerSec = lastMeasuredSpeedBytesPerSec, bytesPerSec > 0 else { return nil }
        return (bytesPerSec * 8.0) / 1_000_000.0
    }

    var formattedSpeed: String {
        guard let mbps = currentDownloadSpeedMbps, let mBps = currentDownloadSpeedMBps else {
            return "Not Measured"
        }
        if mBps >= 1.0 {
            return String(format: "%.1f MB/s (%.1f Mbps)", mBps, mbps)
        } else {
            let kBps = (lastMeasuredSpeedBytesPerSec ?? 0) / 1000.0
            return String(format: "%.0f KB/s (%.1f Mbps)", kBps, mbps)
        }
    }

    var formattedLatency: String? {
        guard let ms = lastMeasuredLatencyMs else { return nil }
        return String(format: "%.0f ms", ms)
    }

    init() {
        // Default to smallest interval: 15 seconds
        let savedPeriodic = defaults.object(forKey: Keys.periodicEnabled) as? Bool ?? true
        let savedInterval = defaults.integer(forKey: Keys.intervalSeconds)
        self.isPeriodicEnabled = savedPeriodic
        self.intervalSeconds = savedInterval > 0 ? savedInterval : 15

        let savedSpeed = defaults.double(forKey: Keys.lastSpeedBytes)
        if savedSpeed > 0 {
            self.lastMeasuredSpeedBytesPerSec = savedSpeed
            Self.setCachedSpeedMBps(savedSpeed / 1_000_000.0)
        }
        let savedLatency = defaults.double(forKey: Keys.lastLatencyMs)
        if savedLatency > 0 {
            self.lastMeasuredLatencyMs = savedLatency
        }
        let savedTime = defaults.double(forKey: Keys.lastTimestamp)
        if savedTime > 0 {
            self.lastMeasuredAt = Date(timeIntervalSince1970: savedTime)
        }

        detectBinary()
        rescheduleTimer()
    }

    func detectBinary() {
        let candidates = [
            "/opt/homebrew/bin/speedtest",
            "/usr/local/bin/speedtest",
            "/opt/homebrew/bin/speedtest-go",
            "/usr/local/bin/speedtest-go",
            "~/.local/bin/speedtest"
        ]

        let fileManager = FileManager.default
        for path in candidates {
            let expanded = NSString(string: path).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                self.binaryPath = expanded
                self.isAvailable = true
                return
            }
        }

        // Check PATH directories directly without running a synchronous subprocess
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("speedtest").path
            if fileManager.isExecutableFile(atPath: candidate) {
                self.binaryPath = candidate
                self.isAvailable = true
                return
            }
        }

        self.binaryPath = nil
        self.isAvailable = false
    }

    func rescheduleTimer() {
        timer?.invalidate()
        timer = nil

        guard isPeriodicEnabled, isAvailable else { return }

        let interval = TimeInterval(max(5, intervalSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runSpeedTest()
            }
        }
    }

    func runSpeedTest(force: Bool = false) {
        guard isAvailable, let binary = binaryPath else {
            detectBinary()
            guard isAvailable, binaryPath != nil else {
                lastErrorMessage = "speedtest-go binary not found."
                return
            }
            return
        }

        guard !isRunningTest || force else { return }
        isRunningTest = true
        lastErrorMessage = nil

        Task {
            let result = await Task.detached {
                BrewStoreCommandExecutor.shared.run(
                    executablePath: binary,
                    arguments: ["--json", "--no-upload", "--saving-mode"],
                    timeout: 25,
                    category: .readOnly
                )
            }.value

            await MainActor.run {
                self.isRunningTest = false

                if result.succeeded, !result.standardOutput.isEmpty {
                    self.parseJSONOutput(result.standardOutput)
                } else {
                    let err = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastErrorMessage = err.isEmpty ? (result.launchErrorDescription ?? "Speedtest timed out or produced no output.") : err
                }
            }
        }
    }

    private func parseJSONOutput(_ rawOutput: String) {
        // Find JSON block if there's leading/trailing noise
        guard let data = rawOutput.data(using: .utf8) else {
            self.lastErrorMessage = "Failed to encode speedtest output."
            return
        }

        do {
            let parsed = try JSONDecoder().decode(SpeedTestJSONResult.self, from: data)
            if let server = parsed.servers?.first, let speed = server.dl_speed, speed > 0 {
                self.lastMeasuredSpeedBytesPerSec = speed
                if let lat = server.latency {
                    // Latency can be in nanoseconds if large
                    self.lastMeasuredLatencyMs = lat > 1_000_000 ? (lat / 1_000_000.0) : lat
                }
                self.lastMeasuredAt = Date()
                self.lastErrorMessage = nil
            } else {
                self.lastErrorMessage = "No valid download servers returned by speedtest."
            }
        } catch {
            // Try extracting JSON object substring
            if let start = rawOutput.firstIndex(of: "{"), let end = rawOutput.lastIndex(of: "}") {
                let jsonSubstring = String(rawOutput[start ... end])
                if let subData = jsonSubstring.data(using: .utf8),
                   let parsed = try? JSONDecoder().decode(SpeedTestJSONResult.self, from: subData),
                   let server = parsed.servers?.first,
                   let speed = server.dl_speed, speed > 0 {
                    self.lastMeasuredSpeedBytesPerSec = speed
                    if let lat = server.latency {
                        self.lastMeasuredLatencyMs = lat > 1_000_000 ? (lat / 1_000_000.0) : lat
                    }
                    self.lastMeasuredAt = Date()
                    self.lastErrorMessage = nil
                    return
                }
            }
            self.lastErrorMessage = "Malformed speedtest JSON: \(error.localizedDescription)"
        }
    }

    func installSpeedTest(manager: HomebrewManager) {
        manager.perform(
            package: BrewStorePackage(
                id: "speedtest-go",
                name: "speedtest-go",
                description: "CLI and Go API to Test Internet Speed using speedtest.net",
                homepage: "https://github.com/showwin/speedtest-go",
                version: "1.8.3",
                kind: .formula,
                isInstalled: false,
                isOutdated: false,
                dependencies: [],
                caveats: nil,
                installedVersion: nil
            ),
            action: .install
        ) { [weak self] success in
            if success {
                Task { @MainActor in
                    self?.detectBinary()
                    self?.runSpeedTest()
                }
            }
        }
    }
}
