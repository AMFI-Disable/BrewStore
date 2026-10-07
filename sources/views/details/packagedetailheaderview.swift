import SwiftUI

struct PackageDetailHeaderView: View {
    let package: BrewStorePackage
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var preferences = BrewStorePreferences.shared
    @ObservedObject var pinningManager = BrewStorePackagePinningManager.shared
    @ObservedObject var wishlistManager = BrewStoreWishlistManager.shared
    let installedAppIcon: NSImage?
    let matchingKegOnlyItem: KegOnlyPackageItem?
    let matchingOrphanItem: LeafPackageItem?
    let onDismiss: () -> Void
    @Binding var activeSheet: PackageDetailSheet?

    var body: some View {
        let isWishlisted = wishlistManager.isWishlisted(id: package.id)

        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Navigation Bar with Back and Close affordances
            HStack {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back (Esc or ⌘[)")
                .accessibilityIdentifier("PackageDetail.BackButton")

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
                .accessibilityIdentifier("PackageDetail.CloseButton")
            }

            // Identity & Primary Actions Row
            HStack(alignment: .center, spacing: Spacing.md) {
                PackageIconView(package: package, size: 48, cornerRadius: Radius.panel)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(package.name)
                            .font(.title2.bold())
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if package.isInstalled, pinningManager.isPinned(packageID: package.id) {
                            HStack(spacing: 3) {
                                Image(systemName: "pin.fill")
                                Text("Pinned")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                        }

                        if let badge = TrendingRankingsManager.badge(for: package) {
                            HStack(spacing: 3) {
                                Image(systemName: badge.icon)
                                Text(badge.title)
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }

                        if package.isOutdated {
                            let est = BrewStoreUpdateEstimator.estimate(for: package)
                            HStack(spacing: 3) {
                                Image(systemName: "timer").font(.caption2)
                                Text("~\(est.formattedEstimate)")
                                    .font(.caption2.bold().monospaced())
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }

                        if let keg = matchingKegOnlyItem {
                            HStack(spacing: 3) {
                                Image(systemName: keg.isForceLinked ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                                Text(keg.isForceLinked ? "Keg-Only: Force-Linked" : "Keg-Only: Isolated")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(keg.isForceLinked ? .orange : .blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((keg.isForceLinked ? Color.orange : Color.blue).opacity(0.12), in: Capsule())
                        }

                        if let orphan = matchingOrphanItem {
                            HStack(spacing: 3) {
                                Image(systemName: "leaf.fill")
                                Text("Orphan Dependency (\(orphan.formattedSize))")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text(package.id).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        Text("•").font(.caption2).foregroundStyle(.secondary)
                        Text("v\(package.version)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("•").font(.caption2).foregroundStyle(.secondary)
                        Text(package.displayKind).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Action Buttons Bar
                HStack(spacing: 6) {
                    AppStoreActionButton(manager: manager, package: package, size: .regular)

                    if package.isOutdated {
                        Button {
                            activeSheet = .upgradeDiff
                        } label: {
                            Label("Preview Diff", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Preview formula source diff and dependency changes before upgrading")
                    }

                    if package.isInstalled {
                        let isPinned = pinningManager.isPinned(packageID: package.id)
                        let isPinning = pinningManager.isPinningInProgress(packageID: package.id)
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                pinningManager.togglePin(package: package, manager: manager)
                            }
                        } label: {
                            if isPinning {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text(isPinned ? "Unpinning…" : "Pinning…")
                                }
                            } else {
                                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(manager.isOperating || isPinning)
                        .accessibilityIdentifier("PackageDetail.PinButton")
                        .help(isPinned ? "Unpin version to allow updates" : "Pin version to prevent automatic updates")
                    }

                    Button {
                        activeSheet = .advancedInstall
                    } label: {
                        Label("Options", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button {
                        wishlistManager.toggleWishlist(id: package.id)
                    } label: {
                        Image(systemName: isWishlisted ? "star.fill" : "star")
                            .foregroundStyle(isWishlisted ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(isWishlisted ? "Unstar (Remove from Wishlist)" : "Star (Add to Wishlist)")

                    if let url = URL(string: package.homepage), !package.homepage.isEmpty {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Share Package")
                    }
                }
            }
        }
    }
}
