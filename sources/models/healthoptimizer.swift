import Foundation

struct HealthIssueItem: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let severity: String // "warning", "info", "critical"
    let actionTitle: String
    let estimatedSpaceReclaimBytes: Int64?
}

struct HomebrewHealthAssessment: Hashable {
    let score: Int // 0 to 100
    let grade: String // "A+", "A", "B", "C", "D", "F"
    let statusSummary: String
    let issues: [HealthIssueItem]
    let cacheSizeBytes: Int64
    let outdatedCount: Int
    let doctorIssueCount: Int
}

@MainActor
final class BrewStoreHealthOptimizer: ObservableObject {
    @Published var assessment: HomebrewHealthAssessment?
    @Published var isEvaluating = false

    func evaluateHealth(manager: HomebrewManager, doctorDiagnostics: [BrewStoreDoctorDiagnostic]) {
        isEvaluating = true

        let outdatedCount = manager.packages.filter(\.isOutdated).count
        let doctorCount = doctorDiagnostics.count
        let cacheBytes = manager.storageUsage.downloadCacheBytes
        let prefix = manager.brewPrefix ?? (FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local")

        Task.detached(priority: .userInitiated) {
            var score = 100
            var issues: [HealthIssueItem] = []

            // 1. Outdated Packages Check
            if outdatedCount > 0 {
                let penalty = min(25, outdatedCount * 2)
                score -= penalty
                issues.append(HealthIssueItem(
                    id: "outdated-packages",
                    title: "\(outdatedCount) Outdated Package\(outdatedCount == 1 ? "" : "s")",
                    description: "Your system has software versions behind the latest upstream releases.",
                    severity: outdatedCount > 5 ? "critical" : "warning",
                    actionTitle: "Upgrade All",
                    estimatedSpaceReclaimBytes: nil
                ))
            }

            // 2. Doctor Diagnostics Check
            if doctorCount > 0 {
                let penalty = min(30, doctorCount * 5)
                score -= penalty
                issues.append(HealthIssueItem(
                    id: "doctor-issues",
                    title: "\(doctorCount) Homebrew Doctor Warning\(doctorCount == 1 ? "" : "s")",
                    description: "Brew doctor found configuration warnings or outdated permissions.",
                    severity: "warning",
                    actionTitle: "Fix Diagnostics",
                    estimatedSpaceReclaimBytes: nil
                ))
            }

            // 3. Stale Cache Check
            if cacheBytes > 1_000_000_000 { // > 1 GB
                let penalty = (cacheBytes > 5_000_000_000) ? 15 : 8
                score -= penalty
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useGB, .useMB]
                formatter.countStyle = .file
                let formattedSize = formatter.string(fromByteCount: cacheBytes)

                issues.append(HealthIssueItem(
                    id: "stale-cache",
                    title: "Stale Download Cache (\(formattedSize))",
                    description: "Accumulated tarballs, pkg installers, and bottle caches can be reclaimed.",
                    severity: "info",
                    actionTitle: "Clean Cache",
                    estimatedSpaceReclaimBytes: cacheBytes
                ))
            }

            // 4. Stale Homebrew Locks Check
            let hasLocks = BrewStoreLockManager.shared.hasActiveOrStaleLocks(prefix: prefix)
            if hasLocks {
                score -= 20
                issues.append(HealthIssueItem(
                    id: "stale-locks",
                    title: "Active Homebrew Locks Detected",
                    description: "Lock files exist in var/homebrew/locks, which may block package operations and background daemons.",
                    severity: "critical",
                    actionTitle: "Clear Locks",
                    estimatedSpaceReclaimBytes: nil
                ))
            }

            // Ensure bounds
            let finalScore = max(0, min(100, score))
            let grade: String
            let summary: String

            switch finalScore {
            case 95 ... 100:
                grade = "A+"
                summary = "Your Homebrew environment is in optimal peak condition."
            case 90 ... 94:
                grade = "A"
                summary = "Excellent system health with minor maintenance suggestions."
            case 80 ... 89:
                grade = "B"
                summary = "Good condition. Recommended to upgrade outdated packages and clear cache."
            case 70 ... 79:
                grade = "C"
                summary = "Fair condition. Multiple warnings and outdated components detected."
            default:
                grade = "Needs Attention"
                summary = "System health is degraded. Run recommended optimizations below."
            }

            let result = HomebrewHealthAssessment(
                score: finalScore,
                grade: grade,
                statusSummary: summary,
                issues: issues,
                cacheSizeBytes: cacheBytes,
                outdatedCount: outdatedCount,
                doctorIssueCount: doctorCount
            )

            await MainActor.run { [weak self] in
                self?.assessment = result
                self?.isEvaluating = false
            }
        }
    }

    func optimizeAll(manager: HomebrewManager) {
        manager.cleanup()
    }
}
