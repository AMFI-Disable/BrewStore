import AppKit
import Foundation

enum BrewStoreAppIconResolver {
    @MainActor
    static func localAppIcon(for applicationNames: [String]) -> NSImage? {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for appName in applicationNames {
            let normalizedName = appName.hasSuffix(".app") ? appName : "\(appName).app"
            for dir in appDirs {
                let candidate = dir.appendingPathComponent(normalizedName)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return NSWorkspace.shared.icon(forFile: candidate.path)
                }
            }
        }
        return nil
    }

    @MainActor
    static func localAppURL(for applicationNames: [String]) -> URL? {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for appName in applicationNames {
            let normalizedName = appName.hasSuffix(".app") ? appName : "\(appName).app"
            for dir in appDirs {
                let candidate = dir.appendingPathComponent(normalizedName)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }
}
