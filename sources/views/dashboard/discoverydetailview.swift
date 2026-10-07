import AppKit
import SwiftUI

struct DiscoveryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: BrewStoreDiscoveryItem
    @ObservedObject var manager: HomebrewManager
    var onSelectDependency: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    @ObservedObject private var pinningManager = BrewStorePackagePinningManager.shared
    @ObservedObject private var wishlistManager = BrewStoreWishlistManager.shared
    @State private var packageAnalytics: PackageInstallAnalytics?

    init(
        item: BrewStoreDiscoveryItem,
        manager: HomebrewManager,
        onSelectDependency: ((String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.item = item
        self.manager = manager
        self.onSelectDependency = onSelectDependency
        self.onDismiss = onDismiss
        let initial = BrewStoreAnalyticsManager.shared.cachedOrBaseline(packageID: item.id, kind: item.kind)
        _packageAnalytics = State(initialValue: initial)
    }

    private func handleDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var display7d: String {
        packageAnalytics?.formatted7d ?? (item.installCount30Days > 0 ? BrewStoreAnalyticsManager.formatCount(max(1, Int(round(Double(item.installCount30Days) * 7.0 / 30.0)))) : "—")
    }

    private var display30d: String {
        packageAnalytics?.formatted30d ?? (item.installCount30Days > 0 ? BrewStoreAnalyticsManager.formatCount(item.installCount30Days) : "—")
    }

    private var display365d: String {
        packageAnalytics?.formatted365d ?? (item.installCount30Days > 0 ? BrewStoreAnalyticsManager.formatCount(item.installCount30Days * 12) : "—")
    }

    private var installedPackage: BrewStorePackage? {
        manager.packages.first { $0.id == item.id && $0.kind == item.kind }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    PackageIconView(
                        item: item,
                        installedPackage: installedPackage,
                        size: 48,
                        cornerRadius: 10
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name).font(.title.bold())
                        Text(item.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(item.category).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button {
                        handleDismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .keyboardShortcut("[", modifiers: .command)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Back (Esc or ⌘[)")

                    let isWishlisted = wishlistManager.isWishlisted(id: item.id)
                    Button {
                        wishlistManager.toggleWishlist(id: item.id)
                    } label: {
                        Image(systemName: isWishlisted ? "star.fill" : "star")
                            .foregroundStyle(isWishlisted ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(isWishlisted ? "Unstar (Remove from Wishlist)" : "Star (Add to Wishlist)")

                    Button {
                        handleDismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Close (Esc)")
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.body)
                            .lineSpacing(3)
                            .foregroundStyle(.primary)
                    }

                    analyticsPillsView
                }

                metadataGridView

                if !item.aliases.isEmpty {
                    MetadataSection(title: "Aliases", values: item.aliases)
                }
                if !item.dependencies.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dependencies").font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(item.dependencies, id: \.self) { dep in
                                    Button(dep) {
                                        onSelectDependency?(dep)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                if !item.artifacts.isEmpty {
                    MetadataSection(title: "Artifacts", values: item.artifacts)
                }

                HStack {
                    if manager.isAvailable {
                        Button(installedPackage?.isOutdated == true ? "Upgrade" : (installedPackage?.isInstalled == true ? "Installed" : "Install")) {
                            let package = installedPackage ?? BrewStorePackage(
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
                            manager.perform(package: package, action: installedPackage?.isOutdated == true ? .upgrade : .install)
                            handleDismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manager.isOperating || (installedPackage?.isInstalled == true && installedPackage?.isOutdated != true))
                    }

                    if installedPackage?.isInstalled == true, installedPackage?.kind == .formula {
                        let isPinned = pinningManager.isPinned(packageID: item.id)
                        Button {
                            if let pkg = installedPackage {
                                pinningManager.togglePin(package: pkg, manager: manager)
                            }
                        } label: {
                            Label(isPinned ? "Unpin Version" : "Pin Version", systemImage: isPinned ? "pin.slash.fill" : "pin.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.isOperating)
                    }

                    if let url = URL(string: item.homepage), !item.homepage.isEmpty {
                        Link("Homepage", destination: url)
                    }
                    Spacer()
                }

                // Interactive blank space at the bottom to dismiss/go back
                Color.clear
                    .frame(height: 36)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleDismiss()
                    }
            }
            .padding(24)
        }
        .frame(minWidth: 580, minHeight: 440)
        .task {
            packageAnalytics = await BrewStoreAnalyticsManager.shared.fetchAnalytics(packageID: item.id, kind: item.kind)
        }
    }

    private var analyticsPillsView: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("7d:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(display7d)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.2), lineWidth: 1))

            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("30d (1 mo):")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(display30d)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.2), lineWidth: 1))

            HStack(spacing: 5) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("365d (1 yr):")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(display365d)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.2), lineWidth: 1))
        }
    }

    private var metadataGridView: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
            if !item.version.isEmpty {
                GridRow {
                    Text("Version").font(.subheadline).foregroundStyle(.secondary)
                    Text(item.version).font(.subheadline)
                }
            }
            if let license = item.license, !license.isEmpty {
                GridRow {
                    Text("License").font(.subheadline).foregroundStyle(.secondary)
                    Text(license).font(.subheadline)
                }
            }
            if let tap = item.tap, !tap.isEmpty {
                GridRow {
                    Text("Tap").font(.subheadline).foregroundStyle(.secondary)
                    Text(tap).font(.subheadline)
                }
            }
            if let a = packageAnalytics {
                GridRow {
                    Text("7-Day installs").font(.subheadline).foregroundStyle(.secondary)
                    Text(a.install7d.formatted()).font(.subheadline)
                }
                GridRow {
                    Text("30-Day (1 mo) installs").font(.subheadline).foregroundStyle(.secondary)
                    Text(a.install30d.formatted()).font(.subheadline)
                }
                GridRow {
                    Text("365-Day (1 yr) installs").font(.subheadline).foregroundStyle(.secondary)
                    Text(a.install365d.formatted()).font(.subheadline)
                }
            } else if item.installCount30Days > 0 {
                GridRow {
                    Text("30-Day (1 mo) installs").font(.subheadline).foregroundStyle(.secondary)
                    Text(item.installCount30Days.formatted()).font(.subheadline)
                }
            }
        }
    }
}

struct MetadataSection: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(values.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
