import AppKit
import Foundation

struct AppStorageBreakdown: Hashable, Sendable {
    let binaryBytes: Int64
    let cacheBytes: Int64
    let dataBytes: Int64
    let cacheCandidates: [BrewStoreRemovalCandidate]
    let dataCandidates: [BrewStoreRemovalCandidate]

    var totalBytes: Int64 {
        binaryBytes + cacheBytes + dataBytes
    }

    var formattedBinary: String {
        ByteCountFormatter.string(fromByteCount: binaryBytes, countStyle: .file)
    }

    var formattedCache: String {
        ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)
    }

    var formattedData: String {
        ByteCountFormatter.string(fromByteCount: dataBytes, countStyle: .file)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

@MainActor
final class BrewStoreAppStorageInspector: ObservableObject {
    @Published var breakdown: AppStorageBreakdown?
    @Published var isInspecting: Bool = false
    @Published var isCleaning: Bool = false
    @Published var statusMessage: String?
    @Published var lastReclaimedBytes: Int64 = 0

    func inspect(package: BrewStorePackage) {
        guard package.isInstalled else {
            breakdown = nil
            return
        }

        isInspecting = true
        statusMessage = nil

        let appURL = resolveAppURL(for: package)
        let bundleID = appURL.flatMap { Bundle(url: $0)?.bundleIdentifier } ?? ""
        let appName = package.name

        Task.detached(priority: .userInitiated) {
            let result = Self.calculateBreakdown(
                package: package,
                appURL: appURL,
                bundleID: bundleID,
                appName: appName
            )

            await MainActor.run { [weak self] in
                self?.breakdown = result
                self?.isInspecting = false
            }
        }
    }

    func toggleCandidateSelection(url: URL) {
        guard let current = breakdown else { return }
        var updatedCaches = current.cacheCandidates
        if let idx = updatedCaches.firstIndex(where: { $0.url == url }) {
            updatedCaches[idx].isSelected.toggle()
            breakdown = AppStorageBreakdown(
                binaryBytes: current.binaryBytes,
                cacheBytes: current.cacheBytes,
                dataBytes: current.dataBytes,
                cacheCandidates: updatedCaches,
                dataCandidates: current.dataCandidates
            )
        }
    }

    func selectAllCandidates() {
        guard let current = breakdown else { return }
        let updated = current.cacheCandidates.map {
            var c = $0
            c.isSelected = true
            return c
        }
        breakdown = AppStorageBreakdown(
            binaryBytes: current.binaryBytes,
            cacheBytes: current.cacheBytes,
            dataBytes: current.dataBytes,
            cacheCandidates: updated,
            dataCandidates: current.dataCandidates
        )
    }

    func deselectAllCandidates() {
        guard let current = breakdown else { return }
        let updated = current.cacheCandidates.map {
            var c = $0
            c.isSelected = false
            return c
        }
        breakdown = AppStorageBreakdown(
            binaryBytes: current.binaryBytes,
            cacheBytes: current.cacheBytes,
            dataBytes: current.dataBytes,
            cacheCandidates: updated,
            dataCandidates: current.dataCandidates
        )
    }

    func cleanCaches(package: BrewStorePackage) {
        guard let currentBreakdown = breakdown, !currentBreakdown.cacheCandidates.isEmpty else { return }
        executeCacheClean(candidates: currentBreakdown.cacheCandidates, package: package)
    }

    func cleanSelectedCaches(package: BrewStorePackage) {
        guard let currentBreakdown = breakdown else { return }
        let selected = currentBreakdown.cacheCandidates.filter(\.isSelected)
        guard !selected.isEmpty else { return }
        executeCacheClean(candidates: selected, package: package)
    }

    private func executeCacheClean(candidates: [BrewStoreRemovalCandidate], package: BrewStorePackage) {
        isCleaning = true
        statusMessage = nil

        Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let allowedRoots = [
                home.appendingPathComponent("Library/Caches"),
                home.appendingPathComponent("Library/Logs"),
                home.appendingPathComponent("Library/Developer"),
                home.appendingPathComponent(".npm"),
                home.appendingPathComponent(".cargo"),
                home.appendingPathComponent(".gradle"),
                home.appendingPathComponent(".orbstack")
            ]
            let validator = BrewStorePathSafetyValidator(allowedRoots: allowedRoots)
            let executor = BrewStoreTrashExecutor(validator: validator)

            let identity = BrewStoreAppIdentity(
                name: package.name,
                bundleIdentifier: "",
                applicationURL: URL(fileURLWithPath: "/tmp")
            )
            let plan = BrewStoreRemovalPlan(
                application: identity,
                candidates: candidates.map {
                    var c = $0
                    c.isSelected = true
                    return c
                }
            )

            let result = executor.execute(plan: plan)
            var reclaimed: Int64 = 0
            var failureReason: String?
            switch result {
            case let .completed(manifest), let .partiallyCompleted(manifest):
                for url in manifest.movedURLs {
                    if let matched = candidates.first(where: { $0.url == url }) {
                        reclaimed += matched.size
                    }
                }
            case let .failed(reason, _):
                failureReason = reason
            default:
                break
            }

            let finalReclaimed = reclaimed
            let finalFailure = failureReason
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.lastReclaimedBytes = finalReclaimed
                self.isCleaning = false
                if let finalFailure {
                    self.statusMessage = "Clean failed: \(finalFailure)"
                } else if finalReclaimed > 0 {
                    let formatted = ByteCountFormatter.string(fromByteCount: finalReclaimed, countStyle: .file)
                    self.statusMessage = "Safely cleared \(formatted) of caches. App data and logins are intact."
                } else {
                    self.statusMessage = "Caches were already clean."
                }
                // Refresh breakdown
                self.inspect(package: package)
            }
        }
    }

    private func resolveAppURL(for package: BrewStorePackage) -> URL? {
        let fileManager = FileManager.default
        let homeApps = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let names = package.applicationNames.isEmpty ? [package.name] : package.applicationNames

        for name in names {
            let normalized = name.hasSuffix(".app") ? name : "\(name).app"
            let candidates = [
                URL(fileURLWithPath: "/Applications").appendingPathComponent(normalized),
                homeApps.appendingPathComponent(normalized)
            ]
            if let found = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
                return found
            }
        }
        return nil
    }

    nonisolated static func calculateBreakdown(
        package: BrewStorePackage,
        appURL: URL?,
        bundleID: String,
        appName: String
    ) -> AppStorageBreakdown {
        let fm = FileManager.default
        var binarySize: Int64 = 0

        if let appURL, fm.fileExists(atPath: appURL.path) {
            binarySize = computeDirectorySize(url: appURL)
        } else if package.kind == .formula, let cellar = package.cellarURL() {
            binarySize = computeDirectorySize(url: cellar)
        }

        guard !bundleID.isEmpty || !appName.isEmpty else {
            return AppStorageBreakdown(
                binaryBytes: binarySize,
                cacheBytes: 0,
                dataBytes: 0,
                cacheCandidates: [],
                dataCandidates: []
            )
        }

        let identity = BrewStoreAppIdentity(
            name: appName,
            bundleIdentifier: bundleID,
            applicationURL: appURL ?? URL(fileURLWithPath: "/Applications/\(appName).app")
        )
        let plan = BrewStoreAppRemovalScanner().scan(application: identity)

        var cacheCandidates: [BrewStoreRemovalCandidate] = []
        var dataCandidates: [BrewStoreRemovalCandidate] = []
        var cacheBytes: Int64 = 0
        var dataBytes: Int64 = 0

        for candidate in plan.candidates {
            if candidate.kind == .applicationBundle {
                if binarySize == 0 {
                    binarySize = candidate.size
                }
            } else if candidate.kind == .cache || candidate.url.path.contains("/Library/Caches/") {
                cacheCandidates.append(candidate)
                cacheBytes += candidate.size
            } else {
                dataCandidates.append(candidate)
                dataBytes += candidate.size
            }
        }

        // Check for specific developer caches matching this app
        let home = fm.homeDirectoryForCurrentUser
        let lowerName = appName.lowercased()
        var devExtraURLs: [URL] = []
        if lowerName.contains("xcode") {
            devExtraURLs.append(home.appendingPathComponent("Library/Developer/Xcode/DerivedData"))
            devExtraURLs.append(home.appendingPathComponent("Library/Developer/Xcode/Archives"))
            devExtraURLs.append(home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"))
        } else if lowerName.contains("docker") {
            devExtraURLs.append(home.appendingPathComponent("Library/Containers/com.docker.docker/Data"))
        } else if lowerName.contains("orbstack") {
            devExtraURLs.append(home.appendingPathComponent(".orbstack/cache"))
        }

        for extra in devExtraURLs {
            if fm.fileExists(atPath: extra.path), !cacheCandidates.contains(where: { $0.url == extra }) {
                let sz = computeDirectorySize(url: extra)
                if sz > 0 {
                    let cand = BrewStoreRemovalCandidate(url: extra, kind: .cache, size: sz, confidence: .relatedPath, isSelected: true)
                    cacheCandidates.append(cand)
                    cacheBytes += sz
                }
            }
        }

        return AppStorageBreakdown(
            binaryBytes: binarySize,
            cacheBytes: cacheBytes,
            dataBytes: dataBytes,
            cacheCandidates: cacheCandidates,
            dataCandidates: dataCandidates
        )
    }

    nonisolated static func computeDirectorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
