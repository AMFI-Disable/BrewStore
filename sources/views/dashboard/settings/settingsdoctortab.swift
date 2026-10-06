import AppKit
import SwiftUI

struct SettingsDoctorTab: View {
    @ObservedObject var manager: HomebrewManager

    @State private var showingDoctorSheet = false
    @State private var showingUpgradeConfirmation = false
    @State private var showingClearCacheConfirm = false
    @State private var showingOrphanAndKegAuditor = false
    @State private var showingBottleIntegrityAuditor = false
    @State private var showingTapHealthBenchmark = false
    @State private var showingBrewfileManager = false
    @State private var showingCaskQuarantineAuditor = false
    @State private var showingSourceBuildStudio = false

    private var doctorDiagnostics: [BrewStoreDoctorDiagnostic] {
        BrewStoreDoctorParser.parse(manager.outputLog)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            doctorDiagnosticsSection
            maintenanceToolsSection
        }
        .confirmationDialog("Upgrade all Homebrew packages?", isPresented: $showingUpgradeConfirmation, titleVisibility: .visible) {
            Button("Upgrade all packages", role: .destructive) { manager.upgradeAllPackages() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("BrewStore will run brew upgrade for all outdated formulae and casks.")
        }
        .sheet(isPresented: $showingDoctorSheet) {
            DoctorDiagnosticsSheet(manager: manager, diagnostics: doctorDiagnostics)
        }
        .sheet(isPresented: $showingOrphanAndKegAuditor) {
            OrphanAndKegAuditorView(manager: manager)
        }
        .sheet(isPresented: $showingBottleIntegrityAuditor) {
            BottleIntegrityAuditorView(manager: manager)
        }
        .sheet(isPresented: $showingTapHealthBenchmark) {
            TapHealthBenchmarkView(manager: manager)
        }
        .sheet(isPresented: $showingBrewfileManager) {
            BrewfileManagerView(manager: manager)
        }
        .sheet(isPresented: $showingCaskQuarantineAuditor) {
            CaskQuarantineAuditorView(manager: manager)
        }
        .sheet(isPresented: $showingSourceBuildStudio) {
            SourceBuildStudioView(manager: manager)
        }
    }

    private var doctorDiagnosticsSection: some View {
        SettingsCardSection(title: "Homebrew Doctor Diagnostics", icon: "stethoscope") {
            Text("Inspect your system for missing command tools, unlinked kegs, and configuration conflicts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Run Homebrew Doctor") {
                    manager.runDoctor()
                    showingDoctorSheet = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!manager.isAvailable || manager.isOperating)

                Spacer()

                Button("Upgrade All Packages") { showingUpgradeConfirmation = true }
                    .disabled(!manager.isAvailable || manager.isOperating)
            }
        }
    }

    private var maintenanceToolsSection: some View {
        SettingsCardSection(title: "Maintenance Tools", icon: "wrench.and.screwdriver") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 10)], spacing: 10) {
                Button("Clean Disk Cache (brew cleanup)") {
                    showingClearCacheConfirm = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!manager.isAvailable || manager.isOperating)
                .confirmationDialog("Clean Disk Cache?", isPresented: $showingClearCacheConfirm, titleVisibility: .visible) {
                    Button("Run Cleanup (brew cleanup)", role: .destructive) {
                        manager.cleanup()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will run 'brew cleanup' to remove stale lockfiles and outdated download archives for installed formulae and casks.")
                }

                Button("Remove Unused Dependencies", role: .destructive) {
                    BrewStoreUninstallCoordinator.shared.requestAutoremove(manager: manager)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!manager.isAvailable || manager.isOperating)

                Button("Audit Leaves & Keg-Only") {
                    showingOrphanAndKegAuditor = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!manager.isAvailable || manager.isOperating)

                Button("Audit Bottle Integrity") {
                    showingBottleIntegrityAuditor = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!manager.isAvailable || manager.isOperating)

                Button("Tap Health & Benchmark") {
                    showingTapHealthBenchmark = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!manager.isAvailable || manager.isOperating)

                Button("Declarative Brewfile Studio") {
                    showingBrewfileManager = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!manager.isAvailable || manager.isOperating)

                Button("Cask Quarantine Auditor") {
                    showingCaskQuarantineAuditor = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!manager.isAvailable || manager.isOperating)

                Button("Source Compiler & Build Logs") {
                    showingSourceBuildStudio = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!manager.isAvailable || manager.isOperating)
            }
        }
    }
}

private struct DoctorDiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let diagnostics: [BrewStoreDoctorDiagnostic]
    @State private var copiedCommand: String?
    @State private var showingAutoFixConfirmation = false

    private var fixableDiagnostics: [BrewStoreDoctorDiagnostic] {
        diagnostics.filter { $0.isAutoFixable && $0.autoFixCommand != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Homebrew Doctor").font(.title2.bold())
                    Text("Diagnostics and system configuration repair.").foregroundStyle(.secondary)
                }
                Spacer()

                if !fixableDiagnostics.isEmpty {
                    Button("Auto-Fix Issues (\(fixableDiagnostics.count))") {
                        showingAutoFixConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isOperating)
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }

            if manager.isOperating {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(manager.activeOperationTitle ?? "Running Homebrew Doctor…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
            } else if diagnostics.isEmpty {
                ContentUnavailableView("No Diagnostic Results", systemImage: "stethoscope", description: Text("Run Homebrew Doctor to inspect system health."))
            } else {
                List(diagnostics) { diag in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: diag.severity == .clean ? "checkmark.circle.fill" : (diag.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"))
                                .foregroundStyle(diag.severity == .clean ? .green : (diag.severity == .error ? .red : .orange))
                            Text(diag.title).font(.headline)
                            Spacer()

                            if diag.isAutoFixable {
                                Text("Auto-Fixable")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.green)
                            } else if diag.requiresSudo {
                                Text("Terminal / Sudo")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }

                            Text(diag.severity.rawValue)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(diag.severity == .clean ? Color.green.opacity(0.12) : (diag.severity == .error ? Color.red.opacity(0.12) : Color.orange.opacity(0.12)), in: Capsule())
                                .foregroundStyle(diag.severity == .clean ? .green : (diag.severity == .error ? .red : .orange))
                        }

                        MarkdownTextView(markdown: diag.message, baseFont: .caption, lineSpacing: 2)

                        if let cmd = diag.suggestedCommand {
                            HStack {
                                Text(cmd)
                                    .font(.caption.monospaced())
                                    .padding(6)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    .textSelection(.enabled)
                                Spacer()

                                if diag.isAutoFixable {
                                    Button("Fix Now") {
                                        manager.applyDoctorFixes(diagnostics: [diag])
                                    }
                                    .controlSize(.small)
                                    .disabled(manager.isOperating)
                                }

                                Button(copiedCommand == cmd ? "Copied!" : "Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(cmd, forType: .string)
                                    copiedCommand = cmd
                                }
                                .controlSize(.small)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
        .confirmationDialog("Apply Auto-Fixes?", isPresented: $showingAutoFixConfirmation, titleVisibility: .visible) {
            Button("Apply \(fixableDiagnostics.count) Repairs", role: .none) {
                manager.applyDoctorFixes(diagnostics: fixableDiagnostics)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("BrewStore will execute safe Homebrew repair commands sequentially.")
        }
    }
}
