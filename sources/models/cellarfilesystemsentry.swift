import Foundation

/// Real-time FileSystem Sentinel that monitors Homebrew Cellar and Caskroom directories
/// to detect package installations, updates, or removals performed externally in Terminal (CLI drift).
@MainActor
final class CellarFileSystemSentry: ObservableObject {
    static let shared = CellarFileSystemSentry()

    @Published private(set) var isMonitoring = false
    @Published private(set) var lastDriftDetectedAt: Date?
    @Published private(set) var driftEventCount = 0
    @Published private(set) var monitoredPaths: [String] = []

    /// Callback invoked when a debounced drift event fires.
    var onDriftDetected: ((String) -> Void)?

    private let monitorQueue = DispatchQueue(label: "com.amfi-disable.brewstore.cellarsentry", qos: .utility)
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval
    private let targetPaths: [String]

    init(
        targetPaths: [String]? = nil,
        debounceInterval: TimeInterval = 3.0,
        onDriftDetected: ((String) -> Void)? = nil
    ) {
        self.targetPaths = targetPaths ?? Self.defaultPathsToMonitor
        self.debounceInterval = debounceInterval
        self.onDriftDetected = onDriftDetected
    }

    deinit {
        // Cancel active monitors
        for source in sources {
            source.cancel()
        }
        for fd in fileDescriptors {
            close(fd)
        }
    }

    /// Standard Homebrew directory locations across Apple Silicon and Intel Macs.
    static var defaultPathsToMonitor: [String] {
        [
            "/opt/homebrew/Cellar",
            "/opt/homebrew/Caskroom",
            "/usr/local/Cellar",
            "/usr/local/Caskroom"
        ]
    }

    /// Start watching all existing target directories.
    func startMonitoring() {
        guard !isMonitoring else { return }

        stopMonitoring()

        var activePaths: [String] = []
        let fileManager = FileManager.default

        for path in targetPaths {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let fd = open(path, O_EVTONLY | O_CLOEXEC)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .link, .rename, .delete],
                queue: monitorQueue
            )

            source.setEventHandler { [weak self] in
                self?.handleFileSystemEvent(on: path)
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            sources.append(source)
            fileDescriptors.append(fd)
            activePaths.append(path)
        }

        monitoredPaths = activePaths
        isMonitoring = !activePaths.isEmpty
    }

    /// Stop all active file system watchers.
    func stopMonitoring() {
        debounceTask?.cancel()
        debounceTask = nil

        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()

        isMonitoring = false
        monitoredPaths.removeAll()
    }

    /// Debounces rapid multi-file writes during an active brew operation before triggering drift notification.
    nonisolated private func handleFileSystemEvent(on path: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.scheduleDebouncedDrift(from: path)
        }
    }

    /// Schedules or extends the debounce window for external changes.
    func scheduleDebouncedDrift(from path: String) {
        debounceTask?.cancel()
        let interval = debounceInterval

        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return // Cancelled by subsequent event
            }

            guard let self, !Task.isCancelled else { return }
            self.driftEventCount += 1
            let now = Date()
            self.lastDriftDetectedAt = now
            self.onDriftDetected?(path)
        }
    }

    /// Programmatic trigger for testing or manual drift injection.
    func triggerDriftImmediately(path: String = "/opt/homebrew/Cellar") {
        debounceTask?.cancel()
        driftEventCount += 1
        lastDriftDetectedAt = Date()
        onDriftDetected?(path)
    }
}
