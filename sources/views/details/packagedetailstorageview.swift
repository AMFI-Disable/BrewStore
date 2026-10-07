import SwiftUI

struct PackageDetailStorageView: View {
    let package: BrewStorePackage
    @ObservedObject var manager: HomebrewManager
    @ObservedObject var storageInspector: BrewStoreAppStorageInspector
    let isScanningRemoval: Bool
    let removalStatusMessage: String?
    let removalStatusIsSuccess: Bool
    let onScanRemoval: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storage & Cache Breakdown", systemImage: "internaldrive.fill")
                .font(.headline)

            appStorageInspectorContent
        }
        .brewCardStyle(elevation: .subtle, padding: Spacing.md)
    }

    private var appStorageInspectorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown of disk space used by this app's binary, caches, and application data.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if storageInspector.isInspecting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Calculating disk breakdown…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let breakdown = storageInspector.breakdown {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("App Binary")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(breakdown.formattedBinary)
                            .font(.subheadline.bold())
                        Text(package.kind == .cask ? "Application bundle" : "Cellar binary")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Caches & Temp")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if breakdown.cacheBytes > 0 {
                                Text("Reclaimable")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(breakdown.formattedCache)
                            .font(.subheadline.bold())
                            .foregroundStyle(breakdown.cacheBytes > 0 ? .primary : .secondary)
                        Text("Safe to clear")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("App Data & State")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(breakdown.formattedData)
                            .font(.subheadline.bold())
                        Text("Keeps logins & prefs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }

                if let msg = storageInspector.statusMessage {
                    let isError = msg.lowercased().contains("failed") || msg.lowercased().contains("error")
                    HStack(spacing: 6) {
                        Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(isError ? Color.red : Color.green)
                            .font(.caption)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((isError ? Color.red : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }

                if !breakdown.cacheCandidates.isEmpty {
                    DisclosureGroup("Granular Cache Directories (\(breakdown.cacheCandidates.count))") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button("Select All") {
                                    storageInspector.selectAllCandidates()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)

                                Text("·")
                                    .foregroundStyle(.secondary)
                                    .font(.caption2)

                                Button("Deselect All") {
                                    storageInspector.deselectAllCandidates()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)

                                Spacer()

                                let selectedCount = breakdown.cacheCandidates.filter(\.isSelected).count
                                Text("\(selectedCount) of \(breakdown.cacheCandidates.count) selected")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)

                            ForEach(breakdown.cacheCandidates) { cand in
                                HStack(spacing: 8) {
                                    Button {
                                        storageInspector.toggleCandidateSelection(url: cand.url)
                                    } label: {
                                        Image(systemName: cand.isSelected ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(cand.isSelected ? Color.accentColor : Color.secondary)
                                    }
                                    .buttonStyle(.plain)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(cand.url.lastPathComponent)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        Text(cand.url.path)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(cand.formattedSize)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    storageInspector.toggleCandidateSelection(url: cand.url)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption.bold())
                }

                HStack(spacing: 10) {
                    if breakdown.cacheBytes > 0 {
                        let selectedCandidates = breakdown.cacheCandidates.filter(\.isSelected)
                        if selectedCandidates.count < breakdown.cacheCandidates.count, !selectedCandidates.isEmpty {
                            Button {
                                storageInspector.cleanSelectedCaches(package: package)
                            } label: {
                                if storageInspector.isCleaning {
                                    ProgressView().controlSize(.small)
                                } else {
                                    let selectedTotal = selectedCandidates.reduce(0) { $0 + $1.size }
                                    let formattedSel = ByteCountFormatter.string(fromByteCount: selectedTotal, countStyle: .file)
                                    Label("Clean Selected (\(formattedSel))", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(storageInspector.isCleaning || manager.isOperating)
                        }

                        if selectedCandidates.count == breakdown.cacheCandidates.count {
                            Button {
                                storageInspector.cleanCaches(package: package)
                            } label: {
                                if storageInspector.isCleaning {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Clean All Caches (\(breakdown.formattedCache))", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(storageInspector.isCleaning || manager.isOperating)
                        } else {
                            Button {
                                storageInspector.cleanCaches(package: package)
                            } label: {
                                if storageInspector.isCleaning {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Clean All Caches (\(breakdown.formattedCache))", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(storageInspector.isCleaning || manager.isOperating)
                        }
                    }

                    if package.kind == .cask {
                        Button {
                            onScanRemoval()
                        } label: {
                            if isScanningRemoval {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Deep Clean & Uninstall…", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isScanningRemoval || manager.isOperating)
                    }

                    Button {
                        storageInspector.inspect(package: package)
                    } label: {
                        Label("Re-scan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(storageInspector.isInspecting)
                }
            } else {
                Button {
                    storageInspector.inspect(package: package)
                } label: {
                    Label("Inspect App Storage & Caches", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let removalStatusMessage {
                HStack(spacing: 6) {
                    Image(systemName: removalStatusIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(removalStatusIsSuccess ? Color.green : Color.orange)
                    Text(removalStatusMessage)
                        .font(.caption)
                        .foregroundStyle(removalStatusIsSuccess ? Color.primary : Color.orange)
                }
            }
        }
    }
}
