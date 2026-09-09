import AppKit
import Foundation
import UserNotifications

enum AutoUpdateFrequency: String, CaseIterable, Identifiable, Codable {
    case manual = "Manual Only"
    case hourly = "Every Hour"
    case daily = "Daily (Recommended)"
    case weekly = "Weekly"

    var id: String {
        rawValue
    }

    var intervalSeconds: TimeInterval {
        switch self {
        case .manual: 0
        case .hourly: 3600
        case .daily: 86400
        case .weekly: 604800
        }
    }
}

enum AutoUpgradeMode: String, CaseIterable, Identifiable, Codable {
    case disabled = "Notify Only (Manual Upgrades)"
    case cliOnly = "Auto-Upgrade CLI Formulae (Safe & Non-Disruptive)"
    case all = "Auto-Upgrade All (Formulae & GUI Casks)"

    var id: String {
        rawValue
    }
}

@MainActor
final class BrewStoreAutoUpdateScheduler: ObservableObject {
    static let shared = BrewStoreAutoUpdateScheduler()

    @Published var frequency: AutoUpdateFrequency {
        didSet {
            UserDefaults.standard.set(frequency.rawValue, forKey: "brewstore.autoupdate.frequency")
            rescheduleTimer()
        }
    }

    @Published var upgradeMode: AutoUpgradeMode {
        didSet {
            UserDefaults.standard.set(upgradeMode.rawValue, forKey: "brewstore.autoupgrade.mode")
        }
    }

    @Published var autoNotifyOnUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoNotifyOnUpdates, forKey: "brewstore.autoupdate.notify")
        }
    }

    @Published var isAutoUpgrading: Bool = false

    @Published var lastCheckDate: Date? {
        didSet {
            if let lastCheckDate {
                UserDefaults.standard.set(lastCheckDate.timeIntervalSince1970, forKey: "brewstore.autoupdate.lastcheck")
            }
        }
    }

    private var timer: Timer?

    init() {
        let rawFreq = UserDefaults.standard.string(forKey: "brewstore.autoupdate.frequency") ?? AutoUpdateFrequency.hourly.rawValue
        self.frequency = AutoUpdateFrequency(rawValue: rawFreq) ?? .hourly

        let rawUpgrade = UserDefaults.standard.string(forKey: "brewstore.autoupgrade.mode") ?? AutoUpgradeMode.disabled.rawValue
        self.upgradeMode = AutoUpgradeMode(rawValue: rawUpgrade) ?? .disabled

        self.autoNotifyOnUpdates = UserDefaults.standard.object(forKey: "brewstore.autoupdate.notify") as? Bool ?? true

        let lastTimestamp = UserDefaults.standard.double(forKey: "brewstore.autoupdate.lastcheck")
        if lastTimestamp > 0 {
            self.lastCheckDate = Date(timeIntervalSince1970: lastTimestamp)
        }

        requestNotificationPermissions()
        rescheduleTimer()
    }

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func rescheduleTimer() {
        timer?.invalidate()
        timer = nil

        guard frequency != .manual else { return }

        timer = Timer.scheduledTimer(withTimeInterval: frequency.intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performSilentUpdateCheck()
            }
        }
    }

    func performSilentUpdateCheck() {
        lastCheckDate = Date()
        guard let brewPath = HomebrewManager.detectBrewPath() else { return }

        Task.detached(priority: .background) { [brewPath, autoNotify = self.autoNotifyOnUpdates, mode = self.upgradeMode] in
            // 1. Run brew update with timeout
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["update"],
                timeout: 120,
                category: .readOnly
            )

            // 2. Check outdated packages
            let result = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["outdated", "--json=v2"],
                timeout: 30,
                category: .readOnly
            )

            guard result.succeeded, let data = result.standardOutput.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let formulae = json["formulae"] as? [[String: Any]],
                  let casks = json["casks"] as? [[String: Any]] else { return }

            let totalOutdated = formulae.count + casks.count
            guard totalOutdated > 0 else { return }

            if mode == .disabled {
                if autoNotify {
                    Self.dispatchNotification(
                        title: "BrewStore Updates Available",
                        body: "\(totalOutdated) package\(totalOutdated == 1 ? "" : "s") have updates ready to install."
                    )
                }
            } else {
                // Auto-upgrade according to policy
                await MainActor.run {
                    BrewStoreAutoUpdateScheduler.shared.executeAutoUpgrade(
                        formulae: formulae.compactMap { $0["name"] as? String },
                        casks: casks.compactMap { $0["name"] as? String },
                        mode: mode,
                        brewPath: brewPath
                    )
                }
            }
        }
    }

    private func executeAutoUpgrade(formulae: [String], casks: [String], mode: AutoUpgradeMode, brewPath: String) {
        let pinned = BrewStorePackagePinningManager.shared.pinnedPackageIDs
        let eligibleFormulae = formulae.filter { !pinned.contains($0.lowercased()) }
        let eligibleCasks = casks.filter { !pinned.contains($0.lowercased()) }

        var targetPackages: [String] = []
        if mode == .cliOnly {
            targetPackages = eligibleFormulae
        } else if mode == .all {
            targetPackages = eligibleFormulae + eligibleCasks
        }

        guard !targetPackages.isEmpty else { return }
        isAutoUpgrading = true

        Task.detached(priority: .utility) { [targetPackages, brewPath] in
            // Execute upgrade
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["upgrade"] + targetPackages,
                timeout: 300,
                category: .reversibleMutation
            )

            await MainActor.run {
                BrewStoreAutoUpdateScheduler.shared.isAutoUpgrading = false
            }

            Self.dispatchNotification(
                title: "⚡ BrewStore Auto-Upgraded Packages",
                body: "Successfully upgraded \(targetPackages.count) package\(targetPackages.count == 1 ? "" : "s"): \(targetPackages.prefix(4).joined(separator: ", "))"
            )
        }
    }

    nonisolated static func dispatchNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "brewstore.autoupdate.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
