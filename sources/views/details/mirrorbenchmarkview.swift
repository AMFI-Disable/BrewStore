import AppKit
import SwiftUI

struct MirrorBenchmarkView: View {
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var mirrorManager: BrewStoreMirrorManager
    @StateObject private var benchmarkManager = BrewStoreMirrorBenchmarkManager.shared
    @State private var copiedSnippet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Mirror Speed Test").font(.headline)
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("Active: \(mirrorManager.currentPreset.name)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                    Text("Test download mirrors to find the fastest connection for your location.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    Task {
                        await benchmarkManager.benchmarkAll()
                    }
                } label: {
                    if benchmarkManager.isBenchmarking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Measuring…")
                        }
                    } else {
                        Label("Test Mirrors", systemImage: "gauge.with.needle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(benchmarkManager.isBenchmarking)
            }

            // Mirror Endpoints List
            VStack(spacing: 10) {
                ForEach(benchmarkManager.mirrors) { mirror in
                    let isActive = (mirror.id == mirrorManager.selectedPresetID)
                    HStack(spacing: 12) {
                        Image(systemName: mirror.isFastest ? "bolt.circle.fill" : (isActive ? "checkmark.circle.fill" : "network"))
                            .font(.title3)
                            .foregroundStyle(mirror.isFastest ? Color.green : (isActive ? Color.blue : Color.secondary))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(mirror.name).font(.subheadline.bold())
                                if isActive {
                                    Text("ACTIVE")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                                if mirror.isFastest {
                                    Text("Fastest")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(mirror.bottleDomain)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Latency Meter
                        if benchmarkManager.isBenchmarking {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Measuring…")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.orange)
                            }
                        } else if let ms = mirror.latencyMs {
                            HStack(spacing: 8) {
                                Text(mirror.formattedLatency)
                                    .font(.subheadline.monospaced().bold())
                                    .foregroundStyle(ms < 100 ? Color.green : (ms < 300 ? Color.orange : Color.red))

                                Circle()
                                    .fill(ms < 100 ? Color.green : (ms < 300 ? Color.orange : Color.red))
                                    .frame(width: 8, height: 8)
                            }
                        } else {
                            Text("Untested")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Quick Copy Configuration Box
            if let fastest = benchmarkManager.fastestMirror, !benchmarkManager.isBenchmarking {
                let snippet = BrewStoreMirrorBenchmarkManager.generateShellExportSnippet(mirror: fastest)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.orange)
                        Text("Benchmark Recommendation: \(fastest.name)")
                            .font(.headline)
                        Spacer()
                        Text("Fastest: \(fastest.formattedLatency)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }

                    Text("This recommendation is based on live latency tests. Your Active Mirror is currently \(mirrorManager.currentPreset.name). This shell configuration is a recommendation and requires an explicit apply action to update your active mirror.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        if fastest.id != mirrorManager.selectedPresetID {
                            Button {
                                mirrorManager.selectedPresetID = fastest.id
                            } label: {
                                Label("Apply \(fastest.name) as Active Mirror", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("\(fastest.name) is currently active")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                        }

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(snippet, forType: .string)
                            copiedSnippet = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedSnippet = false
                            }
                        } label: {
                            Label(copiedSnippet ? "Copied to Clipboard!" : "Copy Shell Config", systemImage: copiedSnippet ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text(snippet)
                        .font(.caption.monospaced())
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(Color.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .task {
            if benchmarkManager.lastBenchmarkedDate == nil {
                await benchmarkManager.benchmarkAll()
            }
        }
    }
}
