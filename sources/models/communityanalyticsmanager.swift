import Foundation

struct PackageAnalyticsMetrics: Identifiable, Hashable, Codable {
    let id: String
    let installCount30d: Int
    let installCount90d: Int
    let installCount365d: Int
    let monthlyGrowthPercent: Double
    let rank: Int
    let sparklinePoints: [Double]

    var formatted30d: String {
        Self.formatNumber(installCount30d)
    }

    var formatted365d: String {
        Self.formatNumber(installCount365d)
    }

    var isPositiveGrowth: Bool {
        monthlyGrowthPercent >= 0
    }

    var formattedGrowth: String {
        String(format: "%+.1f%%", monthlyGrowthPercent)
    }

    private static func formatNumber(_ num: Int) -> String {
        if num >= 1_000_000 {
            String(format: "%.1fM", Double(num) / 1_000_000.0)
        } else if num >= 1_000 {
            String(format: "%.1fK", Double(num) / 1_000.0)
        } else {
            "\(num)"
        }
    }
}

@MainActor
final class BrewStoreCommunityAnalyticsManager: ObservableObject {
    static let shared = BrewStoreCommunityAnalyticsManager()

    nonisolated static let sampleAnalyticsDatabase: [String: PackageAnalyticsMetrics] = [
        "node": PackageAnalyticsMetrics(id: "node", installCount30d: 480_000, installCount90d: 1_400_000, installCount365d: 5_200_000, monthlyGrowthPercent: 12.4, rank: 1, sparklinePoints: [0.65, 0.70, 0.78, 0.82, 0.88, 0.95, 1.0]),
        "git": PackageAnalyticsMetrics(id: "git", installCount30d: 420_000, installCount90d: 1_250_000, installCount365d: 4_900_000, monthlyGrowthPercent: 8.1, rank: 2, sparklinePoints: [0.75, 0.78, 0.80, 0.84, 0.86, 0.90, 0.94]),
        "python@3.12": PackageAnalyticsMetrics(id: "python@3.12", installCount30d: 390_000, installCount90d: 1_100_000, installCount365d: 3_800_000, monthlyGrowthPercent: 28.6, rank: 3, sparklinePoints: [0.45, 0.52, 0.60, 0.72, 0.80, 0.92, 1.0]),
        "ripgrep": PackageAnalyticsMetrics(id: "ripgrep", installCount30d: 310_000, installCount90d: 910_000, installCount365d: 3_400_000, monthlyGrowthPercent: 15.2, rank: 6, sparklinePoints: [0.60, 0.64, 0.70, 0.75, 0.82, 0.89, 0.96]),
        "fzf": PackageAnalyticsMetrics(id: "fzf", installCount30d: 280_000, installCount90d: 830_000, installCount365d: 3_100_000, monthlyGrowthPercent: 14.0, rank: 8, sparklinePoints: [0.58, 0.62, 0.68, 0.74, 0.80, 0.86, 0.93]),
        "bat": PackageAnalyticsMetrics(id: "bat", installCount30d: 240_000, installCount90d: 710_000, installCount365d: 2_600_000, monthlyGrowthPercent: 18.5, rank: 11, sparklinePoints: [0.50, 0.56, 0.63, 0.71, 0.78, 0.88, 0.98]),
        "mole": PackageAnalyticsMetrics(id: "mole", installCount30d: 145_000, installCount90d: 380_000, installCount365d: 950_000, monthlyGrowthPercent: 64.2, rank: 24, sparklinePoints: [0.20, 0.30, 0.45, 0.60, 0.75, 0.90, 1.0]),
        "uv": PackageAnalyticsMetrics(id: "uv", installCount30d: 260_000, installCount90d: 650_000, installCount365d: 1_200_000, monthlyGrowthPercent: 78.4, rank: 9, sparklinePoints: [0.15, 0.28, 0.42, 0.60, 0.78, 0.92, 1.0]),
        "zed": PackageAnalyticsMetrics(id: "zed", installCount30d: 320_000, installCount90d: 840_000, installCount365d: 2_100_000, monthlyGrowthPercent: 52.1, rank: 5, sparklinePoints: [0.25, 0.38, 0.50, 0.65, 0.80, 0.92, 1.0]),
        "ghostty": PackageAnalyticsMetrics(id: "ghostty", installCount30d: 350_000, installCount90d: 920_000, installCount365d: 1_800_000, monthlyGrowthPercent: 88.0, rank: 4, sparklinePoints: [0.10, 0.25, 0.45, 0.68, 0.82, 0.95, 1.0]),
        "raycast": PackageAnalyticsMetrics(id: "raycast", installCount30d: 410_000, installCount90d: 1_180_000, installCount365d: 4_200_000, monthlyGrowthPercent: 22.0, rank: 2, sparklinePoints: [0.55, 0.62, 0.70, 0.78, 0.85, 0.93, 1.0]),
        "bitwarden": PackageAnalyticsMetrics(id: "bitwarden", installCount30d: 210_000, installCount90d: 620_000, installCount365d: 2_400_000, monthlyGrowthPercent: 11.5, rank: 14, sparklinePoints: [0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95])
    ]

    nonisolated static func analytics(for packageID: String) -> PackageAnalyticsMetrics {
        let cleanID = packageID.lowercased()
        if let exact = sampleAnalyticsDatabase[cleanID] {
            return exact
        }

        // Generate deterministic metrics based on hash for packages without explicit database entries
        let hash = abs(cleanID.hashValue)
        let count30d = max(1_200, (hash % 180_000) + 5_000)
        let count90d = count30d * 3 - (hash % 10_000)
        let count365d = count90d * 4 - (hash % 20_000)
        let growth = Double((hash % 700) - 150) / 10.0
        let rank = (hash % 250) + 15

        let baseVal = 0.4 + Double(hash % 30) / 100.0
        let sparkline = [
            baseVal,
            min(1.0, baseVal + 0.08),
            min(1.0, baseVal + 0.15),
            min(1.0, baseVal + 0.22),
            min(1.0, baseVal + 0.32),
            min(1.0, baseVal + 0.45),
            1.0
        ]

        return PackageAnalyticsMetrics(
            id: packageID,
            installCount30d: count30d,
            installCount90d: count90d,
            installCount365d: count365d,
            monthlyGrowthPercent: growth,
            rank: rank,
            sparklinePoints: sparkline
        )
    }
}
