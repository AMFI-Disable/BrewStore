import Foundation
import UserNotifications

@MainActor
final class BrewStoreUpdateMonitor: ObservableObject {
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var isChecking = false
    @Published var lastCheckDate: Date? {
        didSet {
            if let date = lastCheckDate {
                UserDefaults.standard.set(date, forKey: lastCheckKey)
            }
        }
    }

    var isAutoCheckEnabled: Bool {
        get { BrewStorePreferences.shared.isAutoCheckEnabled }
        set {
            BrewStorePreferences.shared.isAutoCheckEnabled = newValue
            if newValue {
                scheduleTimer()
            } else {
                timerTask?.cancel()
            }
            objectWillChange.send()
        }
    }

    var checkIntervalHours: Int {
        get { BrewStorePreferences.shared.checkIntervalHours }
        set {
            BrewStorePreferences.shared.checkIntervalHours = newValue
            scheduleTimer()
            objectWillChange.send()
        }
    }

    private let lastCheckKey = "BrewStoreLastCheckDate"
    private var timerTask: Task<Void, Never>?
    private weak var manager: HomebrewManager?

    init(manager: HomebrewManager? = nil) {
        self.manager = manager
        self.lastCheckDate = UserDefaults.standard.object(forKey: lastCheckKey) as? Date

        checkNotificationStatus()
        if BrewStorePreferences.shared.isAutoCheckEnabled {
            scheduleTimer()
        }
    }

    func setManager(_ manager: HomebrewManager) {
        self.manager = manager
    }

    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            Task { @MainActor in
                self.checkNotificationStatus()
            }
        }
    }

    func checkForUpdatesNow(forceNotification: Bool = false) {
        guard let manager, manager.isAvailable, !manager.isOperating, !isChecking else { return }
        isChecking = true

        Task {
            if BrewStorePreferences.shared.autoFetchMetadata {
                manager.updateHomebrew()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            manager.refresh()
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            await MainActor.run {
                self.isChecking = false
                self.lastCheckDate = Date()
                let outdated = manager.packages.filter(\.isOutdated)
                BrewStoreDockLifecycleManager.shared.updateBadge(outdatedCount: outdated.count)
                if !outdated.isEmpty || forceNotification {
                    self.postUpdateNotification(outdatedPackages: outdated)
                }
            }
        }
    }

    func scheduleTimer() {
        timerTask?.cancel()
        guard BrewStorePreferences.shared.isAutoCheckEnabled else { return }

        let intervalSeconds = UInt64(max(BrewStorePreferences.shared.checkIntervalHours, 1)) * 3600

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.checkForUpdatesNow()
                }
            }
        }
    }

    private func postUpdateNotification(outdatedPackages: [BrewStorePackage]) {
        guard BrewStorePreferences.shared.showNotifications else { return }
        guard !outdatedPackages.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(outdatedPackages.count) Homebrew Update\(outdatedPackages.count == 1 ? "" : "s") Available"
        let names = outdatedPackages.prefix(3).map(\.name).joined(separator: ", ")
        content.body = outdatedPackages.count > 3 ? "\(names), and \(outdatedPackages.count - 3) more are ready to upgrade." : "\(names) ready to upgrade."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "brewstore-updates-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
