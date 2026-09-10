import AppKit
import SwiftUI

/// macOS Native Quick Look preview HUD for Homebrew packages.
struct BrewStoreQuickLookView: View {
    let package: BrewStorePackage
    @ObservedObject var manager: HomebrewManager
    var onOpenDetail: () -> Void
    var onDismiss: () -> Void

    private var currentPackage: BrewStorePackage {
        manager.packages.first { $0.id == package.id && $0.kind == package.kind } ?? package
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 14) {
                if currentPackage.kind == .cask,
                   let icon = BrewStoreAppIconResolver.localAppIcon(for: currentPackage.applicationNames.isEmpty ? [currentPackage.name] : currentPackage.applicationNames) {
                    Image(nsImage: icon)
                        .resizable().scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: currentPackage.kind == .cask ? "app.fill" : "terminal.fill")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.tint)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(currentPackage.name)
                            .font(.title2.bold())
                            .lineLimit(1)

                        Text(currentPackage.displayVersion)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text(currentPackage.displayKind)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())

                        if let tap = currentPackage.tap {
                            Text(tap)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if currentPackage.isInstalled {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(currentPackage.isOutdated ? "Update Available" : "Installed")
                            }
                            .font(.caption2.bold())
                            .foregroundStyle(currentPackage.isOutdated ? Color.orange : Color.green)
                        }
                    }
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss Preview (Escape or Space)")
            }

            Divider()

            // Description
            Text(currentPackage.description.isEmpty ? "No description available." : currentPackage.description)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            // Metadata Chips
            HStack(spacing: 12) {
                quickStat(
                    icon: "tag.fill",
                    title: "License",
                    value: BrewStorePackageFilterEngine.isProprietary(package: currentPackage) ? "Proprietary" : "Open Source (FOSS)"
                )

                let footprint = BrewStoreBottleFootprintEstimator.estimateFootprint(for: currentPackage)
                quickStat(
                    icon: "internaldrive",
                    title: "Est. Size",
                    value: footprint.formattedFootprintSize
                )

                if !currentPackage.dependencies.isEmpty {
                    quickStat(
                        icon: "cube.fill",
                        title: "Dependencies",
                        value: "\(currentPackage.dependencies.count) libraries"
                    )
                }
            }

            // Caveats Peek
            if let caveats = currentPackage.caveats, !caveats.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Important Caveats", systemImage: "info.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                    Text(caveats.prefix(180) + (caveats.count > 180 ? "…" : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)

            Divider()

            // Actions
            HStack {
                Button {
                    onOpenDetail()
                } label: {
                    Label("Open Full Details", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                AppStoreActionButton(manager: manager, package: currentPackage)
            }
        }
        .padding(20)
        .frame(width: 520, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
    }

    private func quickStat(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.bold())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
