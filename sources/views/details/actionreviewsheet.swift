import SwiftUI

struct BrewStoreActionReviewSheet: View {
    let request: BrewStoreActionReviewRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: request.kind.icon)
                    .font(.title)
                    .foregroundStyle(request.accentColor)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(request.title)
                            .font(.title2.bold())

                        if request.isDestructive {
                            Text("Destructive")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                    }

                    Text(request.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Main Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Impacted Items Section
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Items (\(request.items.count))")
                            .font(.headline)

                        VStack(spacing: Spacing.xs) {
                            ForEach(request.items) { item in
                                HStack(alignment: .center, spacing: Spacing.sm) {
                                    Image(systemName: item.icon)
                                        .font(.title3)
                                        .foregroundStyle(item.badgeColor)
                                        .frame(width: 28, height: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.title)
                                                .font(.headline)

                                            if let badge = item.badgeText {
                                                Text(badge)
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 1.5)
                                                    .background(item.badgeColor.opacity(0.12), in: Capsule())
                                                    .foregroundStyle(item.badgeColor)
                                            }
                                        }

                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    if let cmd = item.command {
                                        Text(cmd)
                                            .font(.caption2.monospaced())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: Radius.sm))
                            }
                        }
                    }

                    // Pre-Install Disk Space & Footprint Guard
                    if estimatedFootprintMB > 0 {
                        let isCriticallyLow = (availableDiskSpaceGB ?? 10) < max((estimatedFootprintMB / 1024.0) * 1.5, 3.0)
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: isCriticallyLow ? "exclamationmark.triangle.fill" : "internaldrive.fill")
                                .font(.title3)
                                .foregroundStyle(isCriticallyLow ? Color.orange : Color.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(isCriticallyLow ? "Low Disk Space Advisory" : "Estimated Storage Footprint")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(isCriticallyLow ? Color.orange : Color.primary)

                                    Text("~\(formattedFootprint)")
                                        .font(.caption2.bold().monospacedDigit())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background((isCriticallyLow ? Color.orange : Color.accentColor).opacity(0.12), in: Capsule())
                                        .foregroundStyle(isCriticallyLow ? Color.orange : Color.accentColor)
                                }

                                if let freeGB = availableDiskSpaceGB {
                                    Text(isCriticallyLow 
                                         ? "Drive has only \(String(format: "%.1f GB", freeGB)) available. Ensure you maintain sufficient disk buffer."
                                         : "\(String(format: "%.1f GB", freeGB)) available on local APFS volume.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(10)
                        .background((isCriticallyLow ? Color.orange : Color.secondary).opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .stroke((isCriticallyLow ? Color.orange : Color.secondary).opacity(0.15), lineWidth: 1)
                        )
                    }

                    // Command Preview Section
                    if let cmdPreview = request.commandPreview, !cmdPreview.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Planned Homebrew Execution")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Text(cmdPreview)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                                .textSelection(.enabled)
                        }
                    }

                    // Advisory Notes
                    if !request.notes.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            ForEach(request.notes, id: \.self) { note in
                                HStack(alignment: .top, spacing: Spacing.xs) {
                                    Image(systemName: request.isDestructive ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(request.accentColor)
                                        .padding(.top, 2)

                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(request.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.sm))
                    }
                }
            }

            // Footer Buttons
            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(request.confirmationTitle, role: request.isDestructive ? .destructive : nil, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(request.accentColor)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.lg)
        .frame(minWidth: 540, minHeight: 380)
    }

    private var estimatedFootprintMB: Double {
        switch request.kind {
        case let .install(pkgs), let .upgrade(pkgs):
            return pkgs.reduce(0.0) { sum, pkg in
                sum + BrewStoreBottleFootprintEstimator.estimateFootprint(for: pkg).estimatedCellarFootprintMB
            }
        default:
            return 0.0
        }
    }

    private var formattedFootprint: String {
        if estimatedFootprintMB >= 1000 {
            return String(format: "%.1f GB", estimatedFootprintMB / 1024.0)
        } else {
            return String(format: "%.1f MB", estimatedFootprintMB)
        }
    }

    private var availableDiskSpaceGB: Double? {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let bytes = values.volumeAvailableCapacityForImportantUsage {
                return Double(bytes) / (1024.0 * 1024.0 * 1024.0)
            }
        } catch {}
        return nil
    }
}
