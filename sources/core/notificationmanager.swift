import Foundation
import UserNotifications

@MainActor
final class BrewStoreNotificationManager: ObservableObject {
    static let shared = BrewStoreNotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        checkStatus()
    }

    func checkStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            Task { @MainActor in
                self.checkStatus()
            }
        }
    }

    func notifyOperationCompleted(action: String, packageName: String, success: Bool) {
        let content = UNMutableNotificationContent()
        content.title = success ? "Package \(action.capitalized) Succeeded" : "Package \(action.capitalized) Failed"
        content.body = success ? "Successfully \(action.lowercased())ed \(packageName)." : "Failed to \(action.lowercased()) \(packageName). Check BrewStore logs for details."
        content.sound = success ? .default : .defaultCritical

        postNotification(identifier: "op-\(packageName)-\(Date().timeIntervalSince1970)", content: content)
    }

    func notifyCacheCleaned(reclaimedBytes: Int64) {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        let formattedSize = formatter.string(fromByteCount: reclaimedBytes)

        let content = UNMutableNotificationContent()
        content.title = "Developer Cache Cleaned"
        content.body = "Reclaimed \(formattedSize) of disk space safely."
        content.sound = .default

        postNotification(identifier: "cache-clean-\(Date().timeIntervalSince1970)", content: content)
    }

    func notifySecurityVulnerability(packageName: String, cveID: String, severity: String) {
        let content = UNMutableNotificationContent()
        content.title = "Security Alert: \(packageName)"
        content.body = "\(cveID) detected with \(severity) severity. An immediate update is recommended."
        content.sound = .defaultCritical

        postNotification(identifier: "cve-\(packageName)-\(cveID)", content: content)
    }

    func notifyMajorUpgradeAvailable(packageName: String, fromVersion: String, toVersion: String) {
        let content = UNMutableNotificationContent()
        content.title = "Major Update: \(packageName)"
        content.body = "New major version available: \(fromVersion) → \(toVersion). Check migration notes before upgrading."
        content.sound = .default

        postNotification(identifier: "major-upg-\(packageName)", content: content)
    }

    // MARK: - Dispatch

    private func postNotification(identifier: String, content: UNNotificationContent) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
