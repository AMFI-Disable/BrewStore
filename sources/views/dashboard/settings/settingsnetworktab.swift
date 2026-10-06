import AppKit
import SwiftUI

struct SettingsNetworkTab: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var mirrorManager = BrewStoreMirrorManager()
    @StateObject private var speedTestManager = BrewStoreSpeedTestManager.shared
    @StateObject private var prefixManager = BrewStorePrefixManager.shared
    @State private var copiedMirrorConfig = false
    @State private var showingDualArchBridge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MirrorBenchmarkView(manager: manager, mirrorManager: mirrorManager)
            speedTestSection
            mirrorsSection
            prefixSwitcherSection
        }
        .sheet(isPresented: $showingDualArchBridge) {
            DualArchitectureBridgeView(manager: manager)
        }
    }

    private var speedTestSection: some View {
        SettingsCardSection(title: "Download Speed Test (speedtest-go)", icon: "speedometer") {
            Text("Uses speedtest-go to measure connection speed and estimate package download times.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if speedTestManager.isAvailable {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("speedtest-go Active")
                            .font(.subheadline.bold())
                        if let path = speedTestManager.binaryPath {
                            Text(path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(speedTestManager.formattedSpeed)
                            .font(.subheadline.bold())
                            .foregroundStyle(speedTestManager.currentDownloadSpeedMBps != nil ? .primary : .secondary)
                        if let at = speedTestManager.lastMeasuredAt {
                            Text("Updated \(at.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                Toggle("Periodic Background Speed Testing", isOn: $speedTestManager.isPeriodicEnabled)

                if speedTestManager.isPeriodicEnabled {
                    Picker("Measurement Frequency", selection: $speedTestManager.intervalSeconds) {
                        Text("15 seconds (Fastest)").tag(15)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                        Text("15 minutes").tag(900)
                    }
                }

                HStack {
                    Button(speedTestManager.isRunningTest ? "Testing Speed…" : "Run Speed Test Now") {
                        speedTestManager.runSpeedTest(force: true)
                    }
                    .controlSize(.small)
                    .disabled(speedTestManager.isRunningTest)

                    if speedTestManager.isRunningTest {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()

                    if let err = speedTestManager.lastErrorMessage {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("speedtest-go Not Installed")
                            .font(.subheadline.bold())
                        Text("Install speedtest-go to get accurate download time estimates for packages.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Install speedtest-go") {
                        speedTestManager.installSpeedTest(manager: manager)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var mirrorsSection: some View {
        SettingsCardSection(title: "Homebrew Mirrors & CDN Presets", icon: "network") {
            Text("Select an optimized regional mirror to accelerate Homebrew bottle downloads and API queries.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Active Mirror", selection: $mirrorManager.selectedPresetID) {
                ForEach(BrewStoreMirrorPreset.allPresets) { preset in
                    HStack {
                        Text(preset.name)
                        if let latency = mirrorManager.formattedLatency(for: preset) {
                            Text("(\(latency))").foregroundStyle(.secondary)
                        }
                    }
                    .tag(preset.id)
                }
            }

            HStack {
                Button(mirrorManager.isTestingLatency ? "Testing Latencies…" : "Test Mirror Latencies") {
                    mirrorManager.testLatencies()
                }
                .controlSize(.small)
                .disabled(mirrorManager.isTestingLatency)

                Spacer()

                let exportScript = """
                export HOMEBREW_API_DOMAIN="\(mirrorManager.currentPreset.brewApiDomain)"
                export HOMEBREW_BOTTLE_DOMAIN="\(mirrorManager.currentPreset.brewBottlesDomain)"
                """

                Button(copiedMirrorConfig ? "Copied!" : "Copy Shell Config") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(exportScript, forType: .string)
                    copiedMirrorConfig = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedMirrorConfig = false }
                }
                .controlSize(.small)
            }
        }
    }

    private var prefixSwitcherSection: some View {
        SettingsCardSection(title: "Dual-Homebrew Prefix & Architecture Switcher", icon: "folder.badge.gearshape") {
            Text("Switch active Homebrew prefix between native Apple Silicon ARM64, Rosetta 2 Intel, and custom installations.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(prefixManager.availablePrefixes) { prefix in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(prefix.name).font(.subheadline.bold())
                            if prefix.isActive {
                                Text("Active")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(prefix.brewExecutablePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if prefix.isAvailable {
                        if !prefix.isActive {
                            Button("Switch to Prefix") {
                                prefixManager.switchPrefix(to: prefix, manager: manager)
                            }
                            .controlSize(.small)
                        }
                    } else {
                        Text("Not Installed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                showingDualArchBridge = true
            } label: {
                Label("Inspect Dual-Architecture Bridge", systemImage: "cpu.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
    }
}
