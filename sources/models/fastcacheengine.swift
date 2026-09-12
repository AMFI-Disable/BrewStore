import CryptoKit
import Foundation

struct FastCacheHeader: Codable, Sendable {
    let timestamp: Date
    let version: String
    let sha256: String
    let packageCount: Int
    let installedCount: Int
    let outdatedCount: Int
    let tapCount: Int
    let serviceCount: Int
}

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

    static var cacheHeaderURL: URL {
        cacheDirectoryURL.appendingPathComponent("catalog_cache_meta.json")
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
            let timestamp = Date()
            let version = "1.0.0"
            let payload = FastCachePayload(
                timestamp: timestamp,
                version: version,
                packages: packages,
                taps: taps,
                services: services
            )
            guard let data = try? JSONEncoder().encode(payload) else { return }

            let hashDigest = SHA256.hash(data: data)
            let sha256 = hashDigest.map { String(format: "%02x", $0) }.joined()

            let header = FastCacheHeader(
                timestamp: timestamp,
                version: version,
                sha256: sha256,
                packageCount: packages.count,
                installedCount: packages.filter(\.isInstalled).count,
                outdatedCount: packages.filter(\.isOutdated).count,
                tapCount: taps.count,
                serviceCount: services.count
            )

            let dir = cacheDirectoryURL
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: cacheFileURL, options: .atomic)

            if let headerData = try? JSONEncoder().encode(header) {
                try? headerData.write(to: cacheHeaderURL, options: .atomic)
            }
        }
    }

    static func loadHeaderSynchronously() -> FastCacheHeader? {
        let file = cacheHeaderURL
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(FastCacheHeader.self, from: data)
    }

    static func loadCacheSynchronously() -> FastCachePayload? {
        let file = cacheFileURL
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(FastCachePayload.self, from: data)
    }

    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheFileURL)
        try? FileManager.default.removeItem(at: cacheHeaderURL)
    }

    static func isCatalogCacheFresh(prefix: String?, maxAgeSeconds: TimeInterval = 1800) -> Bool {
        // Fast path: load sub-millisecond micro-header (<1 KB) to avoid decoding multi-megabyte JSON
        if let header = loadHeaderSynchronously() {
            guard header.packageCount > 0 else { return false }
            return isTimestampFresh(header.timestamp, prefix: prefix, maxAgeSeconds: maxAgeSeconds)
        }

        // Fallback for caches written before metadata header introduction
        guard let payload = loadCacheSynchronously() else { return false }
        guard !payload.packages.isEmpty else { return false }
        return isTimestampFresh(payload.timestamp, prefix: prefix, maxAgeSeconds: maxAgeSeconds)
    }

    private static func isTimestampFresh(_ timestamp: Date, prefix: String?, maxAgeSeconds: TimeInterval) -> Bool {
        let age = Date().timeIntervalSince(timestamp)
        if age > maxAgeSeconds {
            return false
        }

        var pathsToCheck: [String] = []
        if let prefix {
            pathsToCheck.append((prefix as NSString).appendingPathComponent("Library/Taps"))
        }

        let userHome = FileManager.default.homeDirectoryForCurrentUser
        pathsToCheck.append(userHome.appendingPathComponent("Library/Caches/Homebrew/api").path)

        for path in pathsToCheck {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                if modDate > timestamp {
                    return false
                }
            }
        }

        return true
    }
}
