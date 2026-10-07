import AppKit
import SwiftUI

struct DiscoveryRow: View {
    let item: BrewStoreDiscoveryItem
    @ObservedObject var manager: HomebrewManager
    let onDetails: () -> Void

    private var targetPackage: BrewStorePackage {
        manager.packages.first { $0.id == item.id && $0.kind == item.kind } ?? BrewStorePackage(
            id: item.id,
            name: item.name,
            description: item.description,
            homepage: item.homepage,
            version: item.version,
            kind: item.kind,
            applicationNames: item.artifacts,
            isInstalled: false,
            isOutdated: false
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            PackageIconView(
                item: item,
                installedPackage: manager.packages.first { $0.id == item.id && $0.kind == item.kind },
                size: 28,
                cornerRadius: 6
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(item.description.isEmpty ? item.id : item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            AppStoreActionButton(manager: manager, package: targetPackage, size: .small, onShowDetail: onDetails)

            Button(action: onDetails) {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("View package details")
            .accessibilityLabel("View details for \(item.name)")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDetails)
        .brewStorePackageContextMenu(package: targetPackage, manager: manager, onShowDetails: onDetails)
    }
}

struct CompactDiscoveryRow: View {
    let item: BrewStoreDiscoveryItem
    @ObservedObject var manager: HomebrewManager
    let onDetails: () -> Void

    private var targetPackage: BrewStorePackage {
        manager.packages.first { $0.id == item.id && $0.kind == item.kind } ?? BrewStorePackage(
            id: item.id,
            name: item.name,
            description: item.description,
            homepage: item.homepage,
            version: item.version,
            kind: item.kind,
            applicationNames: item.artifacts,
            isInstalled: false,
            isOutdated: false
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            PackageIconView(
                item: item,
                installedPackage: manager.packages.first { $0.id == item.id && $0.kind == item.kind },
                size: 20,
                cornerRadius: 5
            )

            HStack(spacing: 6) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !item.version.isEmpty {
                    Text(item.version)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 160, alignment: .leading)

            Text(item.category)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if item.installCount30Days > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                    Text(BrewStoreAnalyticsManager.formatCount(item.installCount30Days))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            AppStoreActionButton(manager: manager, package: targetPackage, size: .small, onShowDetail: onDetails)

            Button(action: onDetails) {
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("View package details")
            .accessibilityLabel("View details for \(item.name)")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDetails)
        .brewStorePackageContextMenu(package: targetPackage, manager: manager, onShowDetails: onDetails)
    }
}
