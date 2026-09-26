import SwiftUI

struct RemovalBlastRadiusSimulatorView: View {
    let package: BrewStorePackage
    @ObservedObject var manager: HomebrewManager
    var onDismiss: (() -> Void)?
    var onProceedUninstall: (() -> Void)?

    private var blastRadius: UninstallBlastRadius {
        BrewStorePreFlightDependencyChecker.simulateUninstallBlastRadius(
            package: package,
            in: manager.packages,
            services: manager.services
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pre-Removal Blast Radius Simulator")
                        .font(.headline)
                    Text("Impact simulation for '\(package.name)' across reverse dependencies & daemons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Risk Assessment Banner
                    riskBanner

                    // Active Running Daemons Alert
                    if !blastRadius.affectedRunningServices.isEmpty {
                        activeServicesSection
                    }

                    // Transitive Reverse Dependents Breakdown
                    dependentsSection

                    // Dependency Cascade Breakdown (Orphanable vs Retained)
                    cascadeSection
                }
                .padding(20)
            }

            Divider()

            // Footer Actions
            HStack {
                if let onDismiss {
                    Button("Close Simulator", action: onDismiss)
                        .controlSize(.regular)
                }

                Spacer()

                if let onProceedUninstall {
                    Button(role: .destructive) {
                        onDismiss?()
                        onProceedUninstall()
                    } label: {
                        Label("Proceed to Uninstall…", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.regular)
                }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 520)
    }

    // MARK: - Sections

    private var riskBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: blastRadius.riskLevel.icon)
                .font(.system(size: 28))
                .foregroundStyle(blastRadius.riskLevel.badgeColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(blastRadius.riskLevel.rawValue.uppercased())
                        .font(.subheadline.bold())
                        .foregroundStyle(blastRadius.riskLevel.badgeColor)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text("\(blastRadius.transitiveBrokenPackages.count) Downstream Dependents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(riskExplanation)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(14)
        .background(blastRadius.riskLevel.badgeColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(blastRadius.riskLevel.badgeColor.opacity(0.25), lineWidth: 1))
    }

    private var riskExplanation: String {
        switch blastRadius.riskLevel {
        case .zero:
            return "No other installed packages or active daemons depend on '\(package.name)'. It is safe to remove without breaking other software."
        case .moderate:
            return "Removing '\(package.name)' will impact \(blastRadius.transitiveBrokenPackages.count) installed packages. Review the dependent list below before proceeding."
        case .critical:
            if !blastRadius.affectedRunningServices.isEmpty {
                return "CRITICAL: Active system services are currently RUNNING that depend on this library. Uninstalling will abruptly terminate or corrupt them."
            }
            return "CRITICAL: Widespread impact. At least \(blastRadius.transitiveBrokenPackages.count) installed packages depend directly or transitively on this library."
        }
    }

    private var activeServicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Active Background Daemons at Risk", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.red)

            Text("The following background services are currently running. Removing '\(package.name)' will break their shared runtime linkage:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(blastRadius.affectedRunningServices) { srv in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)

                        Text(srv.name)
                            .font(.caption.monospaced().bold())

                        Text("Status: \(srv.status)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let user = srv.user {
                            Text("User: \(user)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.2), lineWidth: 1))
    }

    private var dependentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Downstream Reverse Dependents", systemImage: "arrow.triangle.pull")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(blastRadius.transitiveBrokenPackages.count) impacted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if blastRadius.transitiveBrokenPackages.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No installed packages require '\(package.name)'.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if !blastRadius.brokenDownstreamPackages.isEmpty {
                        Text("Direct Dependents:")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], alignment: .leading, spacing: 6) {
                            ForEach(blastRadius.brokenDownstreamPackages, id: \.self) { dep in
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.red)
                                    Text(dep)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }

                    let indirect = blastRadius.transitiveBrokenPackages.filter { !blastRadius.brokenDownstreamPackages.contains($0) }
                    if !indirect.isEmpty {
                        Text("Transitive Cascade (Indirectly Broken):")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], alignment: .leading, spacing: 6) {
                            ForEach(indirect, id: \.self) { dep in
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.orange)
                                    Text(dep)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var cascadeSection: some View {
        HStack(alignment: .top, spacing: 12) {
            // Orphanable Candidates
            VStack(alignment: .leading, spacing: 6) {
                Label("Orphanable Upon Removal", systemImage: "leaf.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)

                if blastRadius.orphanableDependencies.isEmpty {
                    Text("None. Dependencies are either shared or self-contained.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("These \(blastRadius.orphanableDependencies.count) packages will no longer have any dependents:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(blastRadius.orphanableDependencies.joined(separator: ", "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            // Retained Shared Dependencies
            VStack(alignment: .leading, spacing: 6) {
                Label("Retained Shared Libraries", systemImage: "checkmark.shield.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                if blastRadius.safeSharedDependencies.isEmpty {
                    Text("No shared dependencies retained.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Still required by other installed packages:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(blastRadius.safeSharedDependencies.joined(separator: ", "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
