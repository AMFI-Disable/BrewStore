import AppKit
import SwiftUI

struct AppAdoptionView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var adoptionManager = BrewStoreAppAdoptionManager.shared
    @StateObject private var migrationManager = BrewStoreAppleSiliconMigrationManager.shared

    @State private var activeHubTab = 0 // 0: Direct Cask Adoption, 1: Open-Source Replacements
    @State private var selectedFilter = 0 // 0: Verified Adoptable, 1: Requires Review, 2: All Scanned, 3: Managed
    @State private var searchText = ""
    @State private var selectedAppIDs: Set<String> = []
    @State private var showingMigrationSheet = false
    @State private var itemPendingReview: ScannedAppItem?

    private var filteredApps: [ScannedAppItem] {
        let baseList: [ScannedAppItem] = switch selectedFilter {
        case 0:
            adoptionManager.adoptableApps
        case 1:
            adoptionManager.reviewRequiredApps
        case 2:
            adoptionManager.scannedApps
        case 3:
            adoptionManager.managedApps
        default:
            adoptionManager.scannedApps
        }

        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return baseList
        }
        let q = searchText.lowercased()
        return baseList.filter {
            $0.appName.lowercased().contains(q) ||
                ($0.bundleID?.lowercased().contains(q) == true) ||
                ($0.matchedCask?.id.lowercased().contains(q) == true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            Picker("", selection: $activeHubTab) {
                Text("Adopt Existing Apps (\(adoptionManager.adoptableApps.count + adoptionManager.reviewRequiredApps.count))").tag(0)
                Text("Open-Source Alternatives (\(BrewStoreAppReplacementManager.curatedAlternativeCatalog.count))").tag(1)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 10)

            Divider()

            Group {
                if activeHubTab == 1 {
                    AppReplacementView(manager: manager)
                        .padding(20)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
                            Text("How App Adoption Works").font(.subheadline.bold())
                        }
                        Text("Adopting links apps already installed on your Mac with Homebrew. This lets BrewStore keep them updated automatically without redownloading. Apps with multiple versions or loose matches are flagged for your review so nothing gets replaced accidentally.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                    .padding(.bottom, 6)

                    filterBar
                    Divider()

                    if adoptionManager.isScanning {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Scanning /Applications and ~/Applications for unmanaged macOS apps…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredApps.isEmpty {
                        emptyStateView
                    } else {
                        appsListView
                    }
                }
            }
            .id(activeHubTab)
            .animation(nil, value: activeHubTab)
        }
        .onAppear {
            if adoptionManager.scannedApps.isEmpty {
                adoptionManager.scanApplications(manager: manager)
            }
            migrationManager.scanMigrationCandidates(manager: manager)
        }
        .sheet(isPresented: $showingMigrationSheet) {
            migrationSheetView
        }
        .confirmationDialog(
            "Adopt '\(itemPendingReview?.appName ?? "")' as Cask '\(itemPendingReview?.matchedCask?.id ?? "")'?",
            isPresented: Binding(
                get: { itemPendingReview != nil },
                set: {
                    if !$0 {
                        itemPendingReview = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let item = itemPendingReview {
                Button("Adopt Cask (\(item.matchedCask?.id ?? ""))") {
                    adoptionManager.adoptApp(item: item, manager: manager)
                    itemPendingReview = nil
                }
                Button("Cancel", role: .cancel) {
                    itemPendingReview = nil
                }
            }
        } message: {
            if let item = itemPendingReview {
                let reasons = item.reviewReasons.joined(separator: "\n• ")
                Text("Manual review notice:\n• \(reasons)\n\nPlease verify that this local application is fully compatible with the Homebrew Cask '\(item.matchedCask?.id ?? "")'.")
            }
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("App Adoption Hub").font(.largeTitle.bold())
                    if let count = migrationManager.report?.rosettaIntelCount, count > 0 {
                        Button {
                            showingMigrationSheet = true
                        } label: {
                            Label("\(count) Intel Apps (Rosetta)", systemImage: "bolt.badge.clock.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("View Intel apps that can be migrated to Apple Silicon native binaries")
                    }
                }
                Text("Find apps installed outside Homebrew and manage them here to get automatic updates.")
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                adoptionManager.scanApplications(manager: manager)
            } label: {
                Label("Rescan Apps", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(adoptionManager.isScanning || manager.isOperating)

            if !adoptionManager.adoptableApps.isEmpty {
                if !selectedAppIDs.isEmpty {
                    Button {
                        let toAdopt = adoptionManager.adoptableApps.filter { selectedAppIDs.contains($0.id) }
                        BrewStoreActionReviewCoordinator.shared.requestAdopt(items: toAdopt, manager: manager) {
                            adoptionManager.adoptAll(items: toAdopt, manager: manager)
                            selectedAppIDs.removeAll()
                        }
                    } label: {
                        Label("Adopt Selected (\(selectedAppIDs.count))", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.blue)
                    .disabled(manager.isOperating)

                    Button("Deselect All") {
                        selectedAppIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Select All (\(adoptionManager.adoptableApps.count))") {
                        selectedAppIDs = Set(adoptionManager.adoptableApps.map(\.id))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        BrewStoreActionReviewCoordinator.shared.requestAdopt(items: adoptionManager.adoptableApps, manager: manager) {
                            adoptionManager.adoptAll(items: adoptionManager.adoptableApps, manager: manager)
                        }
                    } label: {
                        Label("Adopt Verified (\(adoptionManager.adoptableApps.count))", systemImage: "arrow.down.app.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manager.isOperating)
                }
            }
        }
        .padding()
    }

    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Picker("Filter", selection: $selectedFilter) {
                    Text("Verified Ready (\(adoptionManager.adoptableApps.count))").tag(0)
                    Text("Requires Review (\(adoptionManager.reviewRequiredApps.count))").tag(1)
                    Text("All Scanned (\(adoptionManager.scannedApps.count))").tag(2)
                    Text("Already Managed (\(adoptionManager.managedApps.count))").tag(3)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                searchField
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("Filter", selection: $selectedFilter) {
                    Text("Verified Ready (\(adoptionManager.adoptableApps.count))").tag(0)
                    Text("Requires Review (\(adoptionManager.reviewRequiredApps.count))").tag(1)
                    Text("All Scanned (\(adoptionManager.scannedApps.count))").tag(2)
                    Text("Already Managed (\(adoptionManager.managedApps.count))").tag(3)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)

                searchField
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        BrewStoreSectionSearchBar(text: $searchText, placeholder: "Search unmanaged apps…", count: filteredApps.count)
            .frame(maxWidth: 280)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            selectedFilter == 0 ? "No Unmanaged Apps Found" : (selectedFilter == 1 ? "No Apps Needing Review" : "No Matching Apps"),
            systemImage: "checkmark.seal.fill",
            description: Text(selectedFilter == 0 ? "All apps matching Homebrew casks are already being managed." : (selectedFilter == 1 ? "No apps need manual review." : "Try adjusting your search query."))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appsListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredApps) { item in
                    appRow(item: item)
                }
            }
            .padding(20)
        }
    }

    private func appRow(item: ScannedAppItem) -> some View {
        HStack(spacing: 14) {
            if item.isAdoptable {
                Button {
                    if selectedAppIDs.contains(item.id) {
                        selectedAppIDs.remove(item.id)
                    } else {
                        selectedAppIDs.insert(item.id)
                    }
                } label: {
                    Image(systemName: selectedAppIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedAppIDs.contains(item.id) ? Color.blue : Color.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            // App Icon
            let icon = NSWorkspace.shared.icon(forFile: item.appPath)
            Image(nsImage: icon)
                .resizable()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.appName).font(.headline)

                    if let ver = item.installedVersion {
                        Text(BrewStorePackage.formatDisplayVersion(ver))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    confidenceBadge(confidence: item.matchConfidence)

                    if item.isFromMacAppStore {
                        HStack(spacing: 3) {
                            Image(systemName: "apple.logo")
                            Text("Mac App Store")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                    }

                    if item.isDualAvailable {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                            Text("Homebrew Available (Recommended)")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                    }

                    if item.isAlreadyManaged {
                        Text("Managed by Homebrew")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    if let cask = item.matchedCask {
                        Text("Cask: \(cask.id)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)

                        Text("Latest: \(cask.displayVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(item.bundleID ?? item.appPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if !item.reviewReasons.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(item.reviewReasons, id: \.self) { reason in
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            if item.isFromMacAppStore, item.matchedCask != nil, !item.isAlreadyManaged {
                Button {
                    BrewStoreActionReviewCoordinator.shared.requestAdopt(item: item, manager: manager) {
                        adoptionManager.convertMASToHomebrew(item: item, manager: manager)
                    }
                } label: {
                    Label("Switch to Homebrew", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
                .disabled(manager.isOperating)
                .help("Convert from Mac App Store to Homebrew Cask management for faster updates without Apple ID prompts.")
            } else if item.isAdoptable {
                Button {
                    BrewStoreActionReviewCoordinator.shared.requestAdopt(item: item, manager: manager) {
                        adoptionManager.adoptApp(item: item, manager: manager)
                    }
                } label: {
                    Label("Adopt", systemImage: "arrow.down.app")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manager.isOperating)
            } else if item.requiresManualReview {
                Button {
                    itemPendingReview = item
                } label: {
                    Label("Review & Adopt…", systemImage: "eye.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.isOperating)
            } else if item.isAlreadyManaged {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selectedAppIDs.contains(item.id) ? Color.blue.opacity(0.4) : Color.secondary.opacity(0.1), lineWidth: selectedAppIDs.contains(item.id) ? 1.5 : 1)
        )
    }

    private func confidenceBadge(confidence: AppMatchConfidence) -> some View {
        Text(confidence.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(confidence.badgeColor).opacity(0.12), in: Capsule())
            .foregroundStyle(badgeColor(confidence.badgeColor))
    }

    private func badgeColor(_ name: String) -> Color {
        switch name {
        case "green": .green
        case "blue": .blue
        case "orange": .orange
        default: .secondary
        }
    }

    private var migrationSheetView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Silicon Native Migration Wizard").font(.title2.bold())
                    Text("Migrate Intel (x86_64 Rosetta 2) packages to native Apple Silicon (arm64) binaries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { showingMigrationSheet = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()
            .background(Color.secondary.opacity(0.04))

            Divider()

            if let report = migrationManager.report {
                ScrollView {
                    VStack(spacing: 20) {
                        // Summary Hero
                        HStack(spacing: 20) {
                            metricBox(title: "NATIVE ARM64", count: report.nativeArm64Count, color: .green, icon: "cpu.fill")
                            metricBox(title: "UNIVERSAL 2", count: report.universalCount, color: .blue, icon: "circle.grid.cross.fill")
                            metricBox(title: "INTEL ROSETTA", count: report.rosettaIntelCount, color: report.rosettaIntelCount > 0 ? .orange : .secondary, icon: "bolt.badge.clock.fill")
                        }

                        if report.isFullyOptimized {
                            ContentUnavailableView(
                                "Fully Optimized for Apple Silicon",
                                systemImage: "sparkles",
                                description: Text("All installed packages and applications are running native Apple Silicon or Universal 2 binaries.")
                            )
                            .padding(.top, 40)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Packages Requiring Migration (\(report.migrationRequiredCandidates.count))")
                                        .font(.headline)
                                    Spacer()
                                    Button {
                                        migrationManager.migrateAllRosettaPackages(manager: manager)
                                    } label: {
                                        Label("Migrate All to Native ARM64", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    .controlSize(.small)
                                    .disabled(manager.isOperating)
                                }

                                ForEach(report.migrationRequiredCandidates) { cand in
                                    HStack(spacing: 12) {
                                        Image(systemName: cand.package.kind == .cask ? "app.fill" : "terminal.fill")
                                            .foregroundStyle(cand.package.kind == .cask ? .blue : .green)
                                            .font(.title3)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(cand.package.name).font(.headline)
                                            Text("Architecture: Intel (x86_64 Rosetta 2)")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }

                                        Spacer()

                                        Button("Migrate") {
                                            manager.perform(package: cand.package, action: .reinstall)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .disabled(manager.isOperating)
                                    }
                                    .padding(12)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 480)
    }

    private func metricBox(title: String, count: Int, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
            }
            Text("\(count)")
                .font(.title.bold())
                .foregroundStyle(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
