import Foundation

struct FastCachePayload: Codable {
    let timestamp: Date
    let version: String
    let packages: [BrewStorePackage]
    let taps: [BrewStoreTap]
    let services: [BrewStoreService]
}

enum BrewStoreFastCacheEngine {
    private static let lock = NSLock()
    private static var lastSavedSignature: Int = 0

    static var cacheDirectoryURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("BrewStore", isDirectory: true)
    }

    static var cacheFileURL: URL {
        cacheDirectoryURL.appendingPathComponent("catalog_cache.json")
    }

    static func saveCache(packages: [BrewStorePackage], taps: [BrewStoreTap], services: [BrewStoreService], force: Bool = false) {
        var hasher = Hasher()
        hasher.combine(packages.count)
        hasher.combine(taps.count)
        hasher.combine(services.count)
        for p in packages where p.isInstalled {
            hasher.combine(p.id)
            hasher.combine(p.installedVersion)
            hasher.combine(p.isOutdated)
        }
        let currentSignature = hasher.finalize()

        lock.lock()
        if !force, currentSignature == lastSavedSignature {
            lock.unlock()
            return
        }
        lastSavedSignature = currentSignature
        lock.unlock()

        Task.detached(priority: .background) {
            let payload = FastCachePayload(
                timestamp: Date(),
                version: "1.0.0",
                packages: packages,
                taps: taps,
                services: services
            )
            guard let data = try? JSONEncoder().encode(payload) else { return }

            let dir = cacheDirectoryURL
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }

    static func loadCacheSynchronously() -> FastCachePayload? {
        let file = cacheFileURL
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(FastCachePayload.self, from: data)
    }

    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    static func isCatalogCacheFresh(prefix: String?, maxAgeSeconds: TimeInterval = 1800) -> Bool {
        guard let payload = loadCacheSynchronously() else { return false }
        guard !payload.packages.isEmpty else { return false }

        // Maximum TTL for in-memory freshness without checking
        let age = Date().timeIntervalSince(payload.timestamp)
        if age > maxAgeSeconds {
            return false
        }

        // Check if Homebrew API caches or Taps have been modified after cache timestamp
        var pathsToCheck: [String] = []
        if let prefix {
            pathsToCheck.append((prefix as NSString).appendingPathComponent("Library/Taps"))
        }

        let userHome = FileManager.default.homeDirectoryForCurrentUser
        pathsToCheck.append(userHome.appendingPathComponent("Library/Caches/Homebrew/api").path)

        for path in pathsToCheck {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                if modDate > payload.timestamp {
                    return false
                }
            }
        }

        return true
    }
}
