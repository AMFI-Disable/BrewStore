import AppKit
import Foundation
import UserNotifications

struct ServiceCrashEvent: Identifiable, Hashable, Codable {
    let id: String
    let serviceName: String
    let timestamp: Date
    let statusDescription: String
}

@MainActor
final class BrewStoreServiceWatchdog: ObservableObject {
    static let shared = BrewStoreServiceWatchdog()

    @Published var isWatchdogEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isWatchdogEnabled, forKey: "brewstore.watchdog.enabled")
            rescheduleTimer()
        }
    }

    @Published var autoRestartOnCrash: Bool {
        didSet {
            UserDefaults.standard.set(autoRestartOnCrash, forKey: "brewstore.watchdog.autorestart")
        }
    }

    @Published var recentCrashEvents: [ServiceCrashEvent] = []
    private var timer: Timer?
    private var lastObservedServiceStatuses: [String: String] = [:]

    init() {
        self.isWatchdogEnabled = UserDefaults.standard.object(forKey: "brewstore.watchdog.enabled") as? Bool ?? true
        self.autoRestartOnCrash = UserDefaults.standard.object(forKey: "brewstore.watchdog.autorestart") as? Bool ?? false
        rescheduleTimer()
    }

    func rescheduleTimer() {
        timer?.invalidate()
        timer = nil

        guard isWatchdogEnabled else { return }

        let newTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateServices()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        self.timer = newTimer
    }

    func evaluateServices() {
        guard let brewPath = HomebrewManager.detectBrewPath() else { return }

        Task.detached(priority: .background) { [weak self] in
            let result = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["services", "list", "--json"],
                timeout: 15,
                category: .readOnly
            )
            guard result.succeeded, let data = result.standardOutput.data(using: .utf8) else { return }
            let services = HomebrewJSONParser.services(from: data)

            await MainActor.run { [weak self] in
                guard let self else { return }
                for s in services {
                    let prevStatus = self.lastObservedServiceStatuses[s.name]
                    self.lastObservedServiceStatuses[s.name] = s.status

                    // If previously started and now error
                    if prevStatus == "started", s.status == "error" || s.status == "unknown" {
                        let event = ServiceCrashEvent(
                            id: UUID().uuidString,
                            serviceName: s.name,
                            timestamp: Date(),
                            statusDescription: "Service entered \(s.status) state unexpectedly."
                        )
                        self.recentCrashEvents.insert(event, at: 0)
                        if self.recentCrashEvents.count > 50 {
                            self.recentCrashEvents = Array(self.recentCrashEvents.prefix(50))
                        }
                        Self.dispatchCrashNotification(serviceName: s.name)

                        if self.autoRestartOnCrash {
                            Task.detached(priority: .userInitiated) {
                                _ = BrewStoreCommandExecutor.shared.run(
                                    executablePath: brewPath,
                                    arguments: ["services", "restart", s.name],
                                    timeout: 30,
                                    category: .reversibleMutation
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    nonisolated static func dispatchCrashNotification(serviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Homebrew Service Alert"
        content.body = "Background service '\(serviceName)' has unexpectedly crashed or stopped."
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "brewstore.servicecrash.\(serviceName).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
