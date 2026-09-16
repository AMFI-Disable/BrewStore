import Foundation

struct UpdateTimeEstimate: Hashable, Codable {
    let totalSeconds: Double
    let caskCount: Int
    let formulaCount: Int
    let caskEstimatedSeconds: Double
    let formulaEstimatedSeconds: Double

    var formattedEstimate: String {
        BrewStoreUpdateEstimator.formatDuration(totalSeconds)
    }

    var detailedSummary: String {
        var parts: [String] = []
        if caskCount > 0 {
            parts.append("\(caskCount) app\(caskCount == 1 ? "" : "s") (\(BrewStoreUpdateEstimator.formatDuration(caskEstimatedSeconds)))")
        }
        if formulaCount > 0 {
            parts.append("\(formulaCount) CLI tool\(formulaCount == 1 ? "" : "s") (\(BrewStoreUpdateEstimator.formatDuration(formulaEstimatedSeconds)))")
        }
        if parts.isEmpty {
            return "No updates needed"
        }
        return parts.joined(separator: " · ")
    }
}

enum BrewStoreUpdateEstimator {
    /// Baseline estimates in seconds
    private static let defaultCaskSeconds: Double = 28.0
    private static let defaultFormulaSeconds: Double = 16.0
    private static let perPackageOverheadSeconds: Double = 2.5

    /// Effective download speed in MB/s (measured dynamically via speedtest-go or fallback to CDN baselines)
    static func effectiveDownloadSpeedMBps(for kind: BrewPackageKind) -> Double {
        if let measuredMBps = BrewStoreSpeedTestManager.cachedDownloadSpeedMBps, measuredMBps.isFinite, measuredMBps >= 0.2 {
            return max(0.5, measuredMBps * 0.85)
        }
        return kind == .cask ? 14.0 : 16.0
    }

    /// Estimate duration for a single package based on footprint heuristics, speedtest bandwidth, and package kind
    static func estimate(for package: BrewStorePackage) -> UpdateTimeEstimate {
        let footprint = BrewStoreBottleFootprintEstimator.estimateFootprint(for: package)
        let rawSpeed = effectiveDownloadSpeedMBps(for: package.kind)
        let downloadSpeed = (rawSpeed.isFinite && rawSpeed > 0) ? rawSpeed : (package.kind == .cask ? 14.0 : 16.0)
        let downloadMB = footprint.estimatedDownloadMB.isFinite ? max(0, footprint.estimatedDownloadMB) : 50.0

        let seconds: Double
        if package.kind == .cask {
            // Casks download dmg/zip (measured speed or ~14 MB/s) + mount & copy to /Applications (~12s)
            let downloadTime = downloadMB / downloadSpeed
            seconds = max(12.0, downloadTime + 12.0)
            return UpdateTimeEstimate(
                totalSeconds: (seconds * 10).rounded() / 10,
                caskCount: 1,
                formulaCount: 0,
                caskEstimatedSeconds: seconds,
                formulaEstimatedSeconds: 0
            )
        } else {
            // Formulae download bottle (measured speed or ~16 MB/s) + pour and link + dependencies
            let downloadTime = footprint.estimatedDownloadMB / downloadSpeed
            let pourTime = 6.0 + Double(package.dependencies.count) * 1.8
            seconds = max(8.0, downloadTime + pourTime)
            return UpdateTimeEstimate(
                totalSeconds: (seconds * 10).rounded() / 10,
                caskCount: 0,
                formulaCount: 1,
                caskEstimatedSeconds: 0,
                formulaEstimatedSeconds: seconds
            )
        }
    }

    /// Estimate duration for a collection of packages to update
    static func estimate(for packages: [BrewStorePackage]) -> UpdateTimeEstimate {
        guard !packages.isEmpty else {
            return UpdateTimeEstimate(
                totalSeconds: 0,
                caskCount: 0,
                formulaCount: 0,
                caskEstimatedSeconds: 0,
                formulaEstimatedSeconds: 0
            )
        }

        var caskTotal: Double = 0
        var formulaTotal: Double = 0
        var casks = 0
        var formulae = 0

        for pkg in packages {
            let single = estimate(for: pkg)
            if pkg.kind == .cask {
                caskTotal += single.totalSeconds
                casks += 1
            } else {
                formulaTotal += single.totalSeconds
                formulae += 1
            }
        }

        let overhead = Double(max(0, packages.count - 1)) * perPackageOverheadSeconds
        let total = caskTotal + formulaTotal + overhead

        return UpdateTimeEstimate(
            totalSeconds: (total * 10).rounded() / 10,
            caskCount: casks,
            formulaCount: formulae,
            caskEstimatedSeconds: caskTotal,
            formulaEstimatedSeconds: formulaTotal
        )
    }

    /// Live dynamic remaining time string when updates are currently executing
    @MainActor
    static func liveRemainingTimeString(manager: HomebrewManager) -> String? {
        guard manager.isOperating else { return nil }

        let title = (manager.activeOperationTitle ?? "").lowercased()
        let isUpgradeOperation = title.contains("upgrade") || title.contains("update all")

        guard isUpgradeOperation else { return nil }

        let outdated = manager.packages.filter(\.isOutdated)
        let initialCount = max(outdated.count, manager.updateSessionInitialCount)

        guard let startTime = manager.updateSessionStartTime else {
            // If start time not recorded, fallback to static estimate of remaining
            let est = estimate(for: outdated)
            guard est.totalSeconds > 0 else { return "Finishing up…" }
            return "~\(est.formattedEstimate) left"
        }

        let elapsed = max(0, Date().timeIntervalSince(startTime))
        let baselineEstimate = estimate(for: outdated).totalSeconds

        let completed = max(0, initialCount - outdated.count)
        if completed > 0, initialCount > 0 {
            let averagePerItem = max(1.0, elapsed / Double(completed))
            let remainingItems = max(1, outdated.count)
            let rawRemaining = averagePerItem * Double(remainingItems)
            let remainingSeconds = rawRemaining.isFinite ? max(5.0, rawRemaining) : 15.0
            return formatRemaining(seconds: remainingSeconds)
        } else {
            let remainingSeconds = max(5.0, baselineEstimate - elapsed)
            return formatRemaining(seconds: remainingSeconds.isFinite ? remainingSeconds : 15.0)
        }
    }

    /// Format seconds into readable duration (e.g. "~45s", "~2m 15s", "~5 mins")
    static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN, seconds >= 0 else {
            return "< 10s"
        }
        let sec = Int(seconds.rounded())
        if sec < 10 {
            return "< 10s"
        } else if sec < 60 {
            return "\(sec)s"
        } else if sec < 3600 {
            let mins = sec / 60
            let remainder = sec % 60
            if remainder < 10 {
                return "\(mins)m"
            } else {
                return "\(mins)m \(remainder)s"
            }
        } else {
            let hours = Double(sec) / 3600.0
            return String(format: "%.1fh", hours)
        }
    }

    /// Format remaining seconds into action message (e.g. "~1m 15s remaining")
    static func formatRemaining(seconds: Double) -> String {
        if seconds <= 6 {
            return "Finishing up…"
        }
        return "~\(formatDuration(seconds)) remaining"
    }
}
