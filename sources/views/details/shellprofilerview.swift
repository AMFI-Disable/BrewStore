import AppKit
import SwiftUI

struct ShellProfilerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var profiler = ShellStartupProfiler.shared
    @State private var copiedSnippet = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if profiler.isProfiling {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(profiler.statusMessage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Spawning interactive subshells to benchmark execution time…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = profiler.latestResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heroGradeCard(result: result)
                        breakdownCard(result: result)
                        if !result.tips.isEmpty {
                            optimizationTipsCard(result: result)
                        }
                        cachedShellenvCard(result: result)
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Shell Latency Not Profiled",
                    systemImage: "gauge.with.needle",
                    description: Text("Benchmark your interactive shell launch time and discover slow startup bottlenecks.")
                )
                .overlay(alignment: .bottom) {
                    Button("Start Benchmark") {
                        Task {
                            await profiler.runProfile()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .task {
            if profiler.latestResult == nil {
                await profiler.runProfile()
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "gauge.with.needle.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .padding(8)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Shell Startup Latency Profiler").font(.title3.bold())
                Text("Diagnose terminal launch speed and optimize Homebrew hooks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !profiler.isProfiling {
                Button {
                    Task {
                        await profiler.runProfile()
                    }
                } label: {
                    Label("Re-run Profile", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
        .background(Color.secondary.opacity(0.04))
    }

    private func heroGradeCard(result: ShellBenchmarkResult) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(result.formattedTotalLatency)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(result.grade.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(colorForGrade(result.grade).opacity(0.15), in: Capsule())
                        .foregroundStyle(colorForGrade(result.grade))
                }

                Text("Measured on \(result.shellPath) (\(result.formattedOverhead))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Clean Shell: \(String(format: "%.1f ms", result.cleanShellLatencyMs))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("User Overhead: \(String(format: "%.1f ms", result.userConfigOverheadMs))")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(colorForGrade(result.grade))
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func breakdownCard(result: ShellBenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Component Latency Breakdown", systemImage: "chart.bar.xaxis")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(result.segments) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(segment.name).font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "%.1f ms (%.0f%%)", segment.latencyMs, segment.impactPercentage))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: min(100, segment.impactPercentage), total: 100)
                            .progressViewStyle(.linear)
                            .tint(segment.impactPercentage > 30 ? .orange : .blue)

                        Text(segment.description)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func optimizationTipsCard(result: ShellBenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recommended Optimizations", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(result.tips) { tip in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(tip.title).font(.subheadline.bold())
                        Spacer()
                        Text(String(format: "Save ~%.0f ms", tip.estimatedSavingsMs))
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }

                    Text(tip.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let snippet = tip.recommendedActionSnippet {
                        HStack {
                            Text(snippet)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                copyToClipboard(snippet)
                            } label: {
                                Image(systemName: copiedSnippet ? "checkmark" : "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func cachedShellenvCard(result: ShellBenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Optimized Static Environment Export", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)

                Spacer()

                Button {
                    copyToClipboard(result.cachedShellenvSnippet)
                } label: {
                    Label(copiedSnippet ? "Copied!" : "Copy Snippet", systemImage: copiedSnippet ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text("Paste this into your ~/.zprofile or ~/.zshrc in place of 'eval \"$(brew shellenv)\"' for instant terminal launches.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(result.cachedShellenvSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func colorForGrade(_ grade: ShellPerformanceGrade) -> Color {
        switch grade {
        case .gradeA: .green
        case .gradeB: .blue
        case .gradeC: .orange
        case .gradeD: .red
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedSnippet = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedSnippet = false
        }
    }
}
