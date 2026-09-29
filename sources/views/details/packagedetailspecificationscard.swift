import SwiftUI

struct PackageDetailSpecificationsCard: View {
    let package: BrewStorePackage
    let packageAnalytics: PackageInstallAnalytics?

    var body: some View {
        let footprint = BrewStoreBottleFootprintEstimator.estimateFootprint(for: package)
        VStack(alignment: .leading, spacing: 8) {
            Text("Specifications").font(.headline)

            VStack(spacing: 6) {
                specRow(
                    title: "Type",
                    value: package.kind == .cask ? "macOS App" : "CLI Binary",
                    icon: package.kind == .cask ? "app.fill" : "terminal.fill"
                )
                Divider()
                specRow(
                    title: "Status",
                    value: package.isInstalled ?
                        (package.isOutdated ? "Update" : "Installed") :
                        "Available",
                    icon: package.isInstalled ? "checkmark.circle.fill" : "circle"
                )
                Divider()
                specRow(title: "Download", value: "~" + footprint.formattedDownloadSize, icon: "arrow.down.circle")
                Divider()
                specRow(title: "Disk Space", value: "~" + footprint.formattedFootprintSize, icon: "internaldrive")
                Divider()
                specRow(title: "30d Installs", value: packageAnalytics?.formatted30d ?? "—", icon: "calendar")
                if package.isOutdated {
                    let est = BrewStoreUpdateEstimator.estimate(for: package)
                    Divider()
                    specRow(title: "Est. Update", value: "~" + est.formattedEstimate, icon: "timer")
                }
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private func specRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tint)
                .frame(width: 14)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
        }
    }
}
