import SwiftUI

struct PackageDetailAnalyticsView: View {
    let package: BrewStorePackage
    let analytics: PackageInstallAnalytics?
    @ObservedObject var analyticsManager: BrewStoreAnalyticsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Popularity & Install Activity", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                if let a = analytics {
                    let badge = a.momentumBadge
                    HStack(spacing: 4) {
                        Image(systemName: badge.symbol)
                        Text(badge.title)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(badge.isPositive ? Color.green : Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((badge.isPositive ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                }
            }

            if let a = analytics {
                HStack(spacing: 8) {
                    analyticsMetricPill(title: "7-Day (1 Wk)", value: a.formatted7d, icon: "flame.fill")
                    analyticsMetricPill(title: "30-Day (1 Mo)", value: a.formatted30d, icon: "calendar")
                    analyticsMetricPill(title: "90-Day (Quarter)", value: a.formatted90d, icon: "calendar.badge.clock")
                    analyticsMetricPill(title: "365-Day (1 Yr)", value: a.formatted365d, icon: "chart.line.uptrend.xyaxis")
                }

                // Direct vs Dependency Split Bar
                if a.installOnRequest30d != nil, a.install30d > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Direct Installs: \(Int(a.directRequestRatio * 100))%")
                                .font(.caption2.bold())
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("Dependency Installs: \(Int((1.0 - a.directRequestRatio) * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor)
                                    .frame(width: max(geo.size.width * CGFloat(a.directRequestRatio) - 2, 0))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: max(geo.size.width * CGFloat(1.0 - a.directRequestRatio), 0))
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.top, 4)
                }
            } else if analyticsManager.isLoading["\(package.kind.rawValue):\(package.id)"] == true {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading install stats from Homebrew…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Install statistics aren't available for this package.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func analyticsMetricPill(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
