import AppKit
import SwiftUI

struct LiveExecutionHUDView: View {
    @ObservedObject var telemetryManager = BrewStoreExecutionTelemetryManager.shared
    @ObservedObject var manager: HomebrewManager

    var body: some View {
        VStack(spacing: 8) {
            // Top Stepper Row
            phaseStepperBar

            // Telemetry Gauge Row
            if manager.isOperating {
                telemetryMetricsRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    private var phaseStepperBar: some View {
        HStack(spacing: 4) {
            ForEach(HomebrewExecutionPhase.allCases) { phase in
                let isCurrent = telemetryManager.currentPhase == phase && manager.isOperating
                let isCompleted = telemetryManager.completedPhases.contains(phase) || (!manager.isOperating && manager.errorMessage == nil)

                HStack(spacing: 4) {
                    if isCurrent {
                        ProgressView()
                            .controlSize(.mini)
                    } else if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.green)
                    } else {
                        Image(systemName: phase.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                    }

                    Text(phase.rawValue)
                        .font(.system(size: 10, weight: isCurrent ? .bold : .regular))
                        .foregroundStyle(isCurrent ? Color.primary : (isCompleted ? Color.secondary : Color.secondary.opacity(0.6)))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    isCurrent
                        ? Color.accentColor.opacity(0.15)
                        : (isCompleted ? Color.green.opacity(0.08) : Color.clear),
                    in: Capsule()
                )

                if phase != HomebrewExecutionPhase.allCases.last {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                }
            }
        }
    }

    private var telemetryMetricsRow: some View {
        HStack(spacing: 12) {
            // Speed Throughput Badge
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.blue)
                Text(telemetryManager.telemetry.throughputDisplay)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.blue)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

            // ETA Badge
            if let eta = telemetryManager.telemetry.etaDisplay {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                    Text("ETA: \(eta)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                }
            }

            // Compilation File Progress
            if let cxx = telemetryManager.telemetry.compilationFileProgress {
                HStack(spacing: 4) {
                    Image(systemName: "hammer.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                    Text(cxx)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.orange)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }

            Spacer()

            // Download progress bar if available
            if let pct = telemetryManager.telemetry.downloadPercentage {
                ProgressView(value: pct, total: 100.0)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                Text("\(Int(pct))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
