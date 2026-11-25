import AppKit
import Foundation

enum BrewStoreAppIconResolver {
    @MainActor private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()
    @MainActor private static var urlCache: [String: URL?] = [:]

    @MainActor
    static func localAppIcon(for applicationNames: [String]) -> NSImage? {
        guard !applicationNames.isEmpty else { return nil }
        let key = applicationNames.joined(separator: "|") as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        guard let url = localAppURL(for: applicationNames) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache.setObject(icon, forKey: key)
        return icon
    }

    @MainActor
    static func localAppURL(for applicationNames: [String]) -> URL? {
        guard !applicationNames.isEmpty else { return nil }
        let key = applicationNames.joined(separator: "|")
        if let cached = urlCache[key] {
            if let url = cached, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            if cached == nil {
                return nil
            }
        }

        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for appName in applicationNames {
            let normalizedName = appName.hasSuffix(".app") ? appName : "\(appName).app"
            for dir in appDirs {
                let candidate = dir.appendingPathComponent(normalizedName)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    urlCache[key] = candidate
                    return candidate
                }
            }
        }
        urlCache[key] = .some(nil)
        return nil
    }

    @MainActor
    static func clearCache() {
        iconCache.removeAllObjects()
        urlCache.removeAll()
    }
}
