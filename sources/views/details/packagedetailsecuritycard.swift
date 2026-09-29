import SwiftUI

struct PackageDetailSecurityCard: View {
    let package: BrewStorePackage
    let manager: HomebrewManager
    let effectivePrefix: String
    @ObservedObject var securityInspector: BrewStoreSecurityInspector
    @ObservedObject var entitlementsAuditor: CaskEntitlementsAuditor
    let caskQuarantineItem: CaskQuarantineItem?
    @Binding var activeSheet: PackageDetailSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Security & Integrity").font(.headline)

            if securityInspector.isInspecting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Inspecting binary…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let report = securityInspector.report {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Architecture").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        let isSilicon = report.architecture == .appleSilicon || report.architecture == .universal2
                        Text(isSilicon ? "Apple Silicon" : "Rosetta 2")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (isSilicon ? Color.green : Color.orange).opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(isSilicon ? Color.green : Color.orange)
                    }

                    Divider()

                    HStack {
                        Text("Signing").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(report.codeSignAuthority).font(.caption.monospaced()).lineLimit(1)
                    }

                    if report.isHardenedRuntime {
                        Divider()
                        HStack {
                            Text("Runtime").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Label("Hardened", systemImage: "lock.shield.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                        }
                    }

                    Divider()

                    if report.isQuarantined {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Quarantine Active", systemImage: "exclamationmark.shield.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button("Remove") {
                                    securityInspector.removeQuarantine(package: package, manager: manager)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            Text("macOS will prompt for approval before launch.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green).font(.caption2)
                            Text("Clean Gatekeeper").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if package.kind == .cask, let entReport = entitlementsAuditor.reportsByPackageID[package.id] {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("App Sandbox").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(entReport.isSandboxed ? "Enforced" : "Unrestricted")
                                    .font(.caption2.bold())
                                    .foregroundStyle(entReport.isSandboxed ? Color.green : Color.secondary)
                            }

                            if !entReport.badges.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        ForEach(entReport.badges) { badge in
                                            Label(badge.title, systemImage: badge.systemImage)
                                                .font(.system(size: 9, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                                .help(badge.description)
                                        }
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "shield").foregroundStyle(.secondary).font(.caption2)
                    Text("Standard Security").font(.caption).foregroundStyle(.secondary)
                }
            }

            if package.kind == .formula {
                Divider()
                let integrity = BrewStoreBottleIntegrityAuditor.auditPackage(package: package, prefix: effectivePrefix)
                Button {
                    activeSheet = .bottleIntegrity
                } label: {
                    HStack {
                        Image(systemName: integrity.status.icon)
                            .font(.caption2)
                            .foregroundStyle(integrityStatusColor(integrity.status))
                        Text("Bottle Integrity").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(integrityStatusLabel(integrity.status))
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                integrityStatusColor(integrity.status).opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(integrityStatusColor(integrity.status))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help("Inspect cryptographic bottle checksums and Cellar Mach-O binaries")
            }

            if package.kind == .cask, package.isInstalled {
                Divider()
                Button {
                    activeSheet = .caskQuarantine
                } label: {
                    HStack {
                        let status = caskQuarantineItem?.status ?? .uninspected
                        Image(systemName: status.iconName)
                            .font(.caption2)
                            .foregroundStyle(status.badgeColor)
                        Text("Gatekeeper & Quarantine").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(status.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                status.badgeColor.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(status.badgeColor)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help("Audit Gatekeeper extended quarantine attributes and code signatures")
            }

            if package.kind == .formula {
                Divider()
                Button {
                    activeSheet = .sourceBuildStudio
                } label: {
                    HStack {
                        Image(systemName: "hammer")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                        Text("Source Compiler Studio").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help("Configure source compilation flags (--build-from-source, --HEAD) and inspect build logs")
            }

            let advisories = BrewStoreCVEScanningManager.advisories(for: package)
            if !advisories.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(advisories) { adv in
                        HStack(spacing: 4) {
                            Image(systemName: adv.severity.symbol)
                                .font(.caption2)
                                .foregroundStyle(adv.severity.color)
                            Text(adv.id).font(.caption2.bold())
                            Spacer()
                            if let url = URL(string: adv.advisoryURL) {
                                Link("Advisory", destination: url)
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private func integrityStatusColor(_ status: BottleIntegrityStatus) -> Color {
        switch status {
        case .verifiedBottle: return .green
        case .builtFromSource: return .purple
        case .unmanagedOrManual: return .orange
        case .corruptedOrTampered: return .red
        }
    }

    private func integrityStatusLabel(_ status: BottleIntegrityStatus) -> String {
        switch status {
        case .verifiedBottle: return "Verified"
        case .builtFromSource: return "Source"
        case .unmanagedOrManual: return "Unmanaged"
        case .corruptedOrTampered: return "Corrupted"
        }
    }
}
