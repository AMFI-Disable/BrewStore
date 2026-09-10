import SwiftUI

struct DiskStorageView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var storageManager = BrewStoreDiskStorageAnalyzerManager.shared
    @ObservedObject private var devCacheManager = BrewStoreDeveloperCacheManager.shared
    @State private var selectedPackageForDetail: BrewStorePackage?
    @State private var selectedFilter: StorageFilter = .all

    enum StorageFilter: String, CaseIterable, Identifiable {
        case all = "All Items"
        case formulae = "Formulae"
        case casks = "Casks"

        var id: String {
            rawValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header & Actions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disk Storage & Cleanup").font(.headline)
                    Text("Inspect package storage, download caches, logs, and old versions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    storageManager.scanStorage(manager: manager)
                    devCacheManager.scanCaches()
                } label: {
                    Label("Re-Scan", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(storageManager.isScanning || devCacheManager.isScanning || manager.isOperating)

                Button(role: .destructive) {
                    storageManager.purgeCache(manager: manager)
                } label: {
                    Label("Clean All Caches", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manager.isOperating)
            }

            if let rep = storageManager.report {
                // Reclaimable Hero Banner
                if rep.reclaimableBytes > 0 {
                    HStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Up to \(rep.formattedReclaimable) can be safely reclaimed")
                                .font(.subheadline.bold())
                            Text("Cleaning download caches (\(rep.formattedTotalCache)), logs (\(rep.formattedTotalLogs)), and inactive versions (\(rep.formattedInactiveVersions)) will free up disk space without affecting your installed tools.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Menu {
                            Button("Clean Download Cache (\(rep.formattedTotalCache))") {
                                storageManager.purgeCache(manager: manager)
                            }
                            Button("Clean Old Build Logs (\(rep.formattedTotalLogs))") {
                                storageManager.purgeLogs(manager: manager)
                            }
                            Button("Remove Inactive Versions (\(rep.formattedInactiveVersions))") {
                                storageManager.purgeInactiveVersions(manager: manager)
                            }
                            Divider()
                            Button("Clean All Safely", role: .destructive) {
                                storageManager.purgeCache(manager: manager)
                                storageManager.purgeLogs(manager: manager)
                                storageManager.purgeInactiveVersions(manager: manager)
                            }
                        } label: {
                            Label("Clean Options…", systemImage: "trash.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                        .disabled(manager.isOperating)
                    }
                    .padding(14)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.2), lineWidth: 1))
                }

                // Metric Stat Summary Cards
                HStack(spacing: 12) {
                    statCard(title: "Installed Packages", value: rep.formattedTotalCellar, icon: "internaldrive.fill", color: .blue)
                    statCard(title: "Download Cache", value: rep.formattedTotalCache, icon: "archivebox.fill", color: .orange)
                    statCard(title: "Build Logs", value: rep.formattedTotalLogs, icon: "doc.text.fill", color: .purple)
                    statCard(title: "Inactive Versions", value: rep.formattedInactiveVersions, icon: "arrow.triangle.swap", color: .pink)
                }

                // Storage Distribution Proportional Treemap Bar
                if rep.totalCellarBytes > 0, !rep.topHogs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Storage Distribution (Top Packages)").font(.subheadline.bold())

                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                ForEach(Array(rep.topHogs.enumerated()), id: \.element.id) { index, hog in
                                    let barColor = colorForIndex(index)
                                    let width = max(geo.size.width * CGFloat(hog.percentageOfTotal) - 2, 4)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(barColor)
                                        .frame(width: width)
                                        .help("\(hog.name): \(hog.formattedSize) (\(Int(hog.percentageOfTotal * 100))%)")
                                }
                            }
                        }
                        .frame(height: 14)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                        // Legend
                        HStack(spacing: 12) {
                            ForEach(Array(rep.topHogs.prefix(4).enumerated()), id: \.element.id) { index, hog in
                                HStack(spacing: 4) {
                                    Circle().fill(colorForIndex(index)).frame(width: 8, height: 8)
                                    Text("\(hog.name) (\(hog.formattedSize))")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }

                // Developer Toolchain Deep-Caches
                developerCachesSection

                // Package Filter & List
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Packages by Disk Usage").font(.subheadline.bold())
                        Spacer()
                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(StorageFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }

                    let filteredItems = rep.items.filter { item in
                        switch selectedFilter {
                        case .all: true
                        case .formulae: item.kind == .formula
                        case .casks: item.kind == .cask
                        }
                    }

                    ForEach(filteredItems.prefix(20)) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.kind == .cask ? "app.fill" : "terminal.fill")
                                .foregroundStyle(item.kind == .cask ? Color.blue : Color.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline.bold())
                                Text(item.path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            }

                            Spacer()

                            Text(item.formattedSize)
                                .font(.subheadline.monospaced().bold())
                                .foregroundStyle(.primary)

                            if let pkg = manager.packages.first(where: { $0.id == item.id }) {
                                Button("Inspect") {
                                    selectedPackageForDetail = pkg
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Calculating disk usage across Cellar, Caskroom, and Caches…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .detailModalOverlay(item: $selectedPackageForDetail) { pkg in
            PackageDetailView(manager: manager, package: pkg, onDismiss: {
                selectedPackageForDetail = nil
            })
        }
        .task {
            storageManager.scanStorage(manager: manager)
            devCacheManager.scanCaches()
        }
    }

    @ViewBuilder
    private var developerCachesSection: some View {
        if devCacheManager.isScanning, devCacheManager.targets.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning developer toolchain caches (Xcode, Docker, Node, Rust)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        } else if !devCacheManager.targets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Developer & Build Caches").font(.subheadline.bold())
                    }

                    Spacer()

                    Button("Select All") {
                        devCacheManager.selectAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Text("·")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Button("Deselect All") {
                        devCacheManager.deselectAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    if devCacheManager.selectedReclaimableBytes > 0 {
                        Button(role: .destructive) {
                            devCacheManager.purgeSelected()
                        } label: {
                            if devCacheManager.isPurging {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Purge Selected (\(devCacheManager.formattedSelectedReclaimable))", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                        .disabled(devCacheManager.isPurging || manager.isOperating)
                    }
                }

                Text("Safely route bloated development caches (Xcode DerivedData, Docker layers, npm/yarn, Cargo) to ~/.Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let status = devCacheManager.statusMessage {
                    let isError = status.lowercased().contains("failed") || status.lowercased().contains("error")
                    HStack(spacing: 6) {
                        Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(isError ? Color.red : Color.green)
                            .font(.caption)
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background((isError ? Color.red : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }

                VStack(spacing: 6) {
                    ForEach(devCacheManager.targets) { target in
                        HStack(spacing: 10) {
                            Button {
                                devCacheManager.toggleTarget(id: target.id)
                            } label: {
                                Image(systemName: target.isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(target.isSelected ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)

                            Image(systemName: target.category.icon)
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(target.name)
                                    .font(.caption.bold())
                                Text(target.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(target.formattedSize)
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(.primary)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            devCacheManager.toggleTarget(id: target.id)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(target.name), \(target.formattedSize), \(target.isSelected ? "Selected" : "Unselected")")
                        .accessibilityHint("Click to toggle selection")
                        .accessibilityAddTraits(target.isSelected ? [.isSelected] : [])
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func colorForIndex(_ index: Int) -> Color {
        let colors: [Color] = [.purple, .blue, .cyan, .teal, .orange, .pink]
        return colors[index % colors.count]
    }
}
