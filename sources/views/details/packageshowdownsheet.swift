import AppKit
import SwiftUI

struct BrewStorePackageShowdownSheet: View {
    let packageA: BrewStorePackage
    let packageB: BrewStorePackage
    @ObservedObject var manager: HomebrewManager
    @Environment(\.dismiss) private var dismiss

    private var currentPackageA: BrewStorePackage {
        manager.packages.first { $0.id == packageA.id && $0.kind == packageA.kind } ?? packageA
    }

    private var currentPackageB: BrewStorePackage {
        manager.packages.first { $0.id == packageB.id && $0.kind == packageB.kind } ?? packageB
    }

    private var footprintA: BottleFootprintInfo {
        BrewStoreBottleFootprintEstimator.estimateFootprint(for: currentPackageA)
    }

    private var footprintB: BottleFootprintInfo {
        BrewStoreBottleFootprintEstimator.estimateFootprint(for: currentPackageB)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Alternative Showdown")
                        .font(.title2.bold())
                    Text("Head-to-head comparison between \(currentPackageA.name) and \(currentPackageB.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(Spacing.lg)

            Divider()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Head-to-Head Cards
                    HStack(spacing: Spacing.md) {
                        packageBannerCard(package: currentPackageA, footprint: footprintA, accent: Color.blue)

                        // VS Badge
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text("VS")
                                        .font(.system(size: 13, weight: .black, design: .rounded))
                                        .foregroundStyle(Color.orange)
                                )
                        }

                        packageBannerCard(package: currentPackageB, footprint: footprintB, accent: Color.purple)
                    }

                    // Comparison Matrix Section
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Specification Matrix")
                            .font(.headline)
                            .padding(.horizontal, 4)

                        VStack(spacing: 1) {
                            comparisonRow(
                                title: "Category & Format",
                                valA: currentPackageA.displayKind,
                                valB: currentPackageB.displayKind
                            )

                            comparisonRow(
                                title: "Status",
                                customA: AnyView(statusBadge(for: currentPackageA)),
                                customB: AnyView(statusBadge(for: currentPackageB))
                            )

                            comparisonRow(
                                title: "Latest Version",
                                valA: currentPackageA.displayVersion,
                                valB: currentPackageB.displayVersion
                            )

                            comparisonRow(
                                title: "Storage Footprint",
                                customA: AnyView(footprintBadge(footprintA, isSmaller: footprintA.estimatedCellarFootprintMB <= footprintB.estimatedCellarFootprintMB)),
                                customB: AnyView(footprintBadge(footprintB, isSmaller: footprintB.estimatedCellarFootprintMB <= footprintA.estimatedCellarFootprintMB))
                            )

                            comparisonRow(
                                title: "Dependencies",
                                valA: currentPackageA.dependencies.isEmpty ? "None (Self-contained)" : "\(currentPackageA.dependencies.count) (\(currentPackageA.dependencies.prefix(2).joined(separator: ", "))\(currentPackageA.dependencies.count > 2 ? "…" : ""))",
                                valB: currentPackageB.dependencies.isEmpty ? "None (Self-contained)" : "\(currentPackageB.dependencies.count) (\(currentPackageB.dependencies.prefix(2).joined(separator: ", "))\(currentPackageB.dependencies.count > 2 ? "…" : ""))"
                            )

                            if let tapA = currentPackageA.tap, let tapB = currentPackageB.tap {
                                comparisonRow(
                                    title: "Repository / Tap",
                                    valA: tapA,
                                    valB: tapB
                                )
                            }

                            if !currentPackageA.homepage.isEmpty || !currentPackageB.homepage.isEmpty {
                                comparisonRow(
                                    title: "Official Homepage",
                                    customA: AnyView(homepageLink(url: currentPackageA.homepage)),
                                    customB: AnyView(homepageLink(url: currentPackageB.homepage))
                                )
                            }
                        }
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }

                    // Descriptions Section
                    HStack(alignment: .top, spacing: Spacing.md) {
                        descriptionBox(package: currentPackageA)
                        descriptionBox(package: currentPackageB)
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    // MARK: - Banner Card
    private func packageBannerCard(package: BrewStorePackage, footprint: BottleFootprintInfo, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: package.kind == .cask ? "app.fill" : "terminal.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    Text(package.name)
                        .font(.headline.bold())
                        .lineLimit(1)
                    Text(package.displayKind)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack {
                AppStoreActionButton(manager: manager, package: package, size: .regular)
                Spacer()
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Status Badge
    private func statusBadge(for package: BrewStorePackage) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(package.isInstalled ? (package.isOutdated ? Color.orange : Color.green) : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(package.isInstalled ? (package.isOutdated ? "Update Available" : "Installed") : "Not Installed")
                .font(.caption.bold())
                .foregroundStyle(package.isInstalled ? (package.isOutdated ? Color.orange : Color.green) : .secondary)
        }
    }

    // MARK: - Footprint Badge
    private func footprintBadge(_ footprint: BottleFootprintInfo, isSmaller: Bool) -> some View {
        HStack(spacing: 6) {
            Text("~\(footprint.formattedFootprintSize)")
                .font(.caption.monospacedDigit())
            if isSmaller {
                Text("Lighter")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Homepage Link
    private func homepageLink(url: String) -> some View {
        Group {
            if let validURL = URL(string: url), !url.isEmpty {
                Link(destination: validURL) {
                    HStack(spacing: 3) {
                        Text(validURL.host ?? "Website")
                            .font(.caption)
                            .lineLimit(1)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                    }
                }
            } else {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Comparison Matrix Row
    private func comparisonRow(
        title: String,
        valA: String? = nil,
        valB: String? = nil,
        customA: AnyView? = nil,
        customB: AnyView? = nil
    ) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
                .padding(.leading, 12)

            Divider()
                .frame(height: 24)

            Group {
                if let customA {
                    customA
                } else {
                    Text(valA ?? "—")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)

            Divider()
                .frame(height: 24)

            Group {
                if let customB {
                    customB
                } else {
                    Text(valB ?? "—")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Description Box
    private func descriptionBox(package: BrewStorePackage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("About \(package.name)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(package.description.isEmpty ? "No description provided." : package.description)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
