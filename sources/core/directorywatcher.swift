import Foundation

/// Monitors Homebrew filesystem paths (Cellar, Caskroom) for changes caused by external terminal operations.
final class BrewStoreDirectoryWatcher {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var watchedPaths: Set<String> = []
    private let targetPaths: [String]
    private var debounceTask: Task<Void, Never>?
    private let onChange: () -> Void

    init(paths: [String], onChange: @escaping () -> Void) {
        self.targetPaths = paths
        self.onChange = onChange
        for path in paths {
            watch(path: path)
        }
    }

    private func watch(path: String) {
        guard FileManager.default.fileExists(atPath: path), !watchedPaths.contains(path) else { return }
        // Use O_CLOEXEC to prevent leaking file descriptors to spawned child processes
        let fd = open(path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let data = source.data
            if data.contains(.delete) || data.contains(.rename) {
                // Inode changed or recreated; re-arm watcher
                self.watchedPaths.remove(path)
                if let old = self.sources.removeValue(forKey: path) {
                    old.cancel()
                }
                self.scheduleReArm(path: path)
            }
            self.scheduleDebouncedChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sources[path] = source
        watchedPaths.insert(path)
    }

    private func scheduleReArm(path: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.watch(path: path)
        }
    }

    private func checkMissingPaths() {
        for path in targetPaths where !watchedPaths.contains(path) {
            watch(path: path)
        }
    }

    private func scheduleDebouncedChange() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5-second debounce
            guard !Task.isCancelled else { return }
            self?.checkMissingPaths()
            self?.onChange()
        }
    }

    func stop() {
        debounceTask?.cancel()
        for (_, source) in sources {
            source.cancel()
        }
        sources.removeAll()
        watchedPaths.removeAll()
    }

    deinit {
        stop()
    }
}
