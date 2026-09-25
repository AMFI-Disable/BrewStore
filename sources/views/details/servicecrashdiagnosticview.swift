import SwiftUI

struct ServiceCrashDiagnosticView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let service: BrewStoreService
    @StateObject private var diagnostician = ServiceCrashDiagnostician.shared
    @State private var showingPortMatrixSheet = false

    private var diagnosis: ServiceCrashDiagnosis? {
        diagnostician.diagnosis(for: service.name)
    }

    private var isDiagnosing: Bool {
        diagnostician.isDiagnosing[service.name] == true
    }

    private var isRemediating: Bool {
        diagnostician.isRemediating[service.name] == true
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if isDiagnosing {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Analyzing daemon logs and system sockets…")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let diag = diagnosis {
                        diagnosisContent(diag)
                    } else {
                        ContentUnavailableView(
                            "No Crash Signatures Detected",
                            systemImage: "checkmark.shield",
                            description: Text("No common failure patterns found in the logs for '\(service.name)'.")
                        )
                        .padding(.vertical, 40)
                    }
                }
                .padding(Spacing.lg)
            }

            Divider()
            footerBar
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 480, idealHeight: 560)
        .sheet(isPresented: $showingPortMatrixSheet) {
            ServicePortMatrixView(manager: manager)
        }
        .task {
            if diagnosis == nil {
                await diagnostician.diagnoseCrash(for: service, brewPrefix: manager.brewPrefix)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: diagnosis?.issueType.systemImage ?? "stethoscope")
                .font(.title)
                .foregroundStyle(diagnosis?.issueType.tintColor ?? .orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text("\(service.name) Crash Diagnosis")
                        .font(.headline)

                    Text(service.status)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }

                if let diag = diagnosis {
                    Text(diag.issueType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task {
                    await diagnostician.diagnoseCrash(for: service, brewPrefix: manager.brewPrefix)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isDiagnosing || isRemediating)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(Spacing.md)
    }

    @ViewBuilder
    private func diagnosisContent(_ diag: ServiceCrashDiagnosis) -> some View {
        // Summary Card
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Label(diag.headline, systemImage: diag.issueType.systemImage)
                    .font(.title3.bold())
                    .foregroundStyle(diag.issueType.tintColor)
                Spacer()
            }

            Text(diag.explanation)
                .font(.body)
                .foregroundStyle(.primary)

            if let port = diag.affectedPort {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "network")
                    Text("Target Port: \(port)")
                }
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.12), in: Capsule())
                .foregroundStyle(.red)
            }

            if let filePath = diag.affectedFilePath {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "doc.text")
                    Text(filePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)

        // Matched Log Evidence
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("Log Signature / Diagnostic Evidence", systemImage: "text.alignleft")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(diag.matchedLogExcerpt)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.sm)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }

        // Suggested Remediations
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Suggested Healing Actions (\(diag.remediations.count))", systemImage: "bolt.fill")
                .font(.subheadline.bold())

            ForEach(diag.remediations) { remediation in
                remediationRow(remediation)
            }
        }

        if let status = diagnostician.remediationStatus[service.name] {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func remediationRow(_ action: ServiceCrashRemediationAction) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.body.bold())

                    if action.isRecommended {
                        Text("Recommended")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }

                Text(action.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if action.actionType == .openPortMatrix {
                Button("Open Port Matrix") {
                    showingPortMatrixSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if action.isRecommended {
                Button("Auto-Repair") {
                    Task {
                        try? await diagnostician.executeRemediation(action, for: service, manager: manager)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRemediating)
            } else {
                Button("Execute") {
                    Task {
                        try? await diagnostician.executeRemediation(action, for: service, manager: manager)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRemediating)
            }
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private var footerBar: some View {
        HStack {
            if let date = diagnosis?.timestamp {
                Text("Diagnosed \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button("Dismiss") {
                dismiss()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}
