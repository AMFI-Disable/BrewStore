import AppKit
import SwiftUI

struct AppleSiliconRosettaBannerView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject private var migrationManager = BrewStoreAppleSiliconMigrationManager.shared
    @State private var isDismissed = false

    private var rosettaCount: Int {
        migrationManager.report?.rosettaIntelCount ?? 0
    }

    private var shouldShow: Bool {
        !isDismissed &&
            (migrationManager.report?.isAppleSiliconHost == true) &&
            rosettaCount > 0
    }

    var body: some View {
        if shouldShow {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: "cpu.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("You have \(rosettaCount) Intel app\(rosettaCount == 1 ? "" : "s") running under Rosetta 2")
                            .font(.subheadline.bold())
                        Text("Rosetta 2")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }

                    Text("Native Apple Silicon builds improve battery life, memory usage, and launch speed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if let status = migrationManager.migrationStatusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        migrationManager.migrateAllRosettaPackages(manager: manager)
                    } label: {
                        if migrationManager.isMigrating || manager.isOperating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Migrate to Apple Silicon", systemImage: "bolt.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(migrationManager.isMigrating || manager.isOperating)

                    Button {
                        isDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss Banner")
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}
