import Foundation

struct MASReceiptAppRecord: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let installedVersion: String
    let appPath: String
}

enum MASReceiptScanner {
    /// Scans standard application directories for bundles containing a valid App Store `_MASReceipt`.
    static func scanInstalledAppStoreApps(
        directories: [String] = ["/Applications", (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Applications")]
    ) -> [MASReceiptAppRecord] {
        let fileManager = FileManager.default
        var discoveredApps: [MASReceiptAppRecord] = []

        for dir in directories {
            guard let items = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let appPath = (dir as NSString).appendingPathComponent(item)
                let receiptPath = ((appPath as NSString).appendingPathComponent("Contents/_MASReceipt") as NSString).appendingPathComponent("receipt")

                if fileManager.fileExists(atPath: receiptPath) {
                    if let record = parseAppBundle(atPath: appPath) {
                        discoveredApps.append(record)
                    }
                }
            }
        }

        return discoveredApps
    }

    /// Reads Info.plist metadata from an application bundle.
    static func parseAppBundle(atPath appPath: String) -> MASReceiptAppRecord? {
        let plistPath = ((appPath as NSString).appendingPathComponent("Contents") as NSString).appendingPathComponent("Info.plist")
        guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else {
            return nil
        }

        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String) ?? "1.0"
        let appName = (plist["CFBundleDisplayName"] as? String) ??
            (plist["CFBundleName"] as? String) ??
            ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension

        let id = bundleID.isEmpty ? appName : bundleID

        return MASReceiptAppRecord(
            id: id,
            name: appName,
            bundleIdentifier: bundleID,
            installedVersion: version,
            appPath: appPath
        )
    }
}
