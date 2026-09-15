import AppKit
import SwiftUI

struct StacksView: View {
    @ObservedObject var manager: HomebrewManager
    @StateObject private var stackManager = BrewStoreStackManager.shared
    @ObservedObject private var preferences = BrewStorePreferences.shared
    @State private var selectedType: BundleType = .all
    @State private var searchQuery = ""
    @State private var showingNewStackSheet = false
    @State private var importErrorMessage: String?
    @State private var showingImportErrorAlert = false

    private var baseStacks: [BrewStoreStack] {
        let base = stackManager.stacks(for: selectedType)
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return base
        }
        let q = searchQuery.lowercased()
        return base.filter {
            $0.name.lowercased().contains(q) ||
                $0.description.lowercased().contains(q) ||
                $0.formulae.contains(where: { $0.lowercased().contains(q) }) ||
                $0.casks.contains(where: { $0.lowercased().contains(q) })
        }
    }

    private var completedBundlesCount: Int {
        baseStacks.filter { $0.isFullyInstalled(in: manager.packages) }.count
    }

    private var filteredStacks: [BrewStoreStack] {
        if preferences.hideCompletedBundles {
            return baseStacks.filter { !$0.isFullyInstalled(in: manager.packages) }
        }
        return baseStacks
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header Bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Formulae & Cask Bundles").font(.title2.bold())
                        Text("Curated open-source software suites and developer environments with batch installation.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Menu {
                            Button {
                                captureSetup()
                            } label: {
                                Label("Capture Local Setup as Blueprint", systemImage: "laptopcomputer")
                            }

                            Button {
                                importBlueprintFile()
                            } label: {
                                Label("Import Blueprint File…", systemImage: "square.and.arrow.down")
                            }
                        } label: {
                            Label("Blueprints", systemImage: "doc.badge.gearshape")
                        }
                        .controlSize(.small)

                        Button {
                            showingNewStackSheet = true
                        } label: {
                            Label("New Custom Bundle", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                // Filter & Search Controls: Row 1 Category Picker, Row 2 Search Bar & Filter Toggle
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Picker("Category", selection: $selectedType) {
                        ForEach(BundleType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)

                    HStack(spacing: Spacing.sm) {
                        BrewStoreSectionSearchBar(text: $searchQuery, placeholder: "Search bundles & package tools…", count: filteredStacks.count)
                            .frame(maxWidth: 320)

                        if completedBundlesCount > 0 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    preferences.hideCompletedBundles.toggle()
                                }
                            } label: {
                                Label(
                                    preferences.hideCompletedBundles
                                        ? "Hidden 100% Completed (\(completedBundlesCount))"
                                        : "Hide 100% Completed (\(completedBundlesCount))",
                                    systemImage: preferences.hideCompletedBundles ? "eye.slash.fill" : "eye"
                                )
                                .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(preferences.hideCompletedBundles ? .accentColor : .secondary)
                            .help(preferences.hideCompletedBundles ? "Show 100% completed bundles" : "Hide 100% completed bundles to declutter")
                        }

                        Spacer()
                    }
                }

                Divider()

                // Grid of Bundles
                if filteredStacks.isEmpty {
                    if preferences.hideCompletedBundles && completedBundlesCount > 0 {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.green)
                            Text("All Bundles Completed")
                                .font(.title3.bold())
                            Text("All \(completedBundlesCount) bundle\(completedBundlesCount == 1 ? " is" : "s are") 100% installed and hidden to avoid clutter.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    preferences.hideCompletedBundles = false
                                }
                            } label: {
                                Label("Show Completed Bundles", systemImage: "eye")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .padding(.top, Spacing.xs)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xl)
                    } else {
                        ContentUnavailableView(
                            "No Matching Bundles",
                            systemImage: "shippingbox",
                            description: Text("Try adjusting your search term or category filter.")
                        )
                        .padding(.top, Spacing.xl)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 460), spacing: Spacing.md)], spacing: Spacing.md) {
                        ForEach(filteredStacks) { stack in
                            StackCardView(stack: stack, manager: manager) {
                                stackManager.deleteCustomStack(stack)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .sheet(isPresented: $showingNewStackSheet) {
            NewStackSheet { name, desc, icon, formulae, casks in
                stackManager.addCustomStack(name: name, description: desc, icon: icon, formulae: formulae, casks: casks)
            }
        }
        .alert("Import Failed", isPresented: $showingImportErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Unable to import blueprint file.")
        }
    }

    private func captureSetup() {
        let macName = Host.current().localizedName ?? "My Mac"
        _ = stackManager.generateBlueprintFromInstalled(
            name: "\(macName) Setup",
            description: "Workstation snapshot generated from installed packages",
            manager: manager
        )
    }

    private func importBlueprintFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import Blueprint"
        panel.message = "Choose a .brewstore-blueprint or JSON file to import"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                _ = try stackManager.importBlueprint(data: data)
            } catch {
                importErrorMessage = error.localizedDescription
                showingImportErrorAlert = true
            }
        }
    }
}

private struct StackCardView: View {
    let stack: BrewStoreStack
    @ObservedObject var manager: HomebrewManager
    let onDelete: () -> Void

    @State private var copiedBrewfile = false

    private var installedCount: Int {
        stack.installedCount(in: manager.packages)
    }

    private var isFullyInstalled: Bool {
        stack.isFullyInstalled(in: manager.packages)
    }

    private var missing: (formulae: [String], casks: [String]) {
        stack.missingPackages(in: manager.packages)
    }

    private var missingTotal: Int {
        missing.formulae.count + missing.casks.count
    }

    private var installedIDs: Set<String> {
        Set(manager.packages.filter(\.isInstalled).map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: stack.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(stack.name).font(.headline.bold())

                        if stack.isCustom {
                            Text("Custom")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.12), in: Capsule())
                                .foregroundStyle(.purple)
                        }

                        // Pricing Badge
                        Text(stack.pricingTier.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(stack.pricingTier == .freeFOSS ? Color.green.opacity(0.12) : Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(stack.pricingTier == .freeFOSS ? .green : .blue)
                    }

                    Text(LocalizedStringKey(stack.description))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if stack.isCustom {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete custom bundle")
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(installedCount) of \(stack.totalCount) tools installed")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isFullyInstalled {
                        Label("100% Completed", systemImage: "checkmark.circle.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                }

                ProgressView(value: Double(installedCount), total: Double(max(stack.totalCount, 1)))
                    .tint(isFullyInstalled ? .green : .accentColor)
            }

            // Package Flow Chips
            VStack(alignment: .leading, spacing: 8) {
                if !stack.formulae.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Formulae (CLI)").font(.caption2.bold()).foregroundStyle(.secondary)
                        FlowChipsView(items: stack.formulae, installedIDs: installedIDs, isCask: false, manager: manager)
                    }
                }

                if !stack.casks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Casks (GUI)").font(.caption2.bold()).foregroundStyle(.secondary)
                        FlowChipsView(items: stack.casks, installedIDs: installedIDs, isCask: true, manager: manager)
                    }
                }
            }

            Spacer(minLength: 4)

            // Action Buttons (Install & Export to Brewfile)
            HStack(spacing: 10) {
                if isFullyInstalled {
                    Button(action: {}) {
                        HStack {
                            Spacer()
                            Label("All Installed", systemImage: "checkmark")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                } else {
                    Button {
                        installMissingPackages()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Install Missing (\(missingTotal))")
                                .bold()
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isOperating)
                }

                Menu {
                    Button {
                        let brewfile = stack.exportToBrewfile()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(brewfile, forType: .string)
                        copiedBrewfile = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedBrewfile = false
                        }
                    } label: {
                        Label("Copy Brewfile", systemImage: "doc.on.doc")
                    }

                    Button {
                        exportBlueprintFile()
                    } label: {
                        Label("Export Blueprint File…", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label(copiedBrewfile ? "Copied!" : "Export…", systemImage: copiedBrewfile ? "checkmark" : "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Export bundle as Brewfile or .brewstore-blueprint file")
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFullyInstalled ? Color.green.opacity(0.2) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .contextMenu {
            if missingTotal > 0 {
                Button {
                    installMissingPackages()
                } label: {
                    Label("Install Missing (\(missingTotal))", systemImage: "arrow.down.circle")
                }
                .disabled(manager.isOperating)
            }

            Button {
                let brewfile = stack.exportToBrewfile()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(brewfile, forType: .string)
            } label: {
                Label("Copy Bundle Brewfile", systemImage: "doc.on.doc")
            }

            Button {
                exportBlueprintFile()
            } label: {
                Label("Export Blueprint File…", systemImage: "square.and.arrow.up")
            }

            if stack.isCustom {
                Divider()
                Button("Delete Custom Bundle", role: .destructive, action: onDelete)
            }
        }
    }

    private func exportBlueprintFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        let safeName = stack.name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        savePanel.nameFieldStringValue = "\(safeName).brewstore-blueprint"
        savePanel.prompt = "Export Blueprint"
        if savePanel.runModal() == .OK, let url = savePanel.url, let data = BrewStoreStackManager.shared.exportBlueprint(stack: stack) {
            try? data.write(to: url)
        }
    }

    private func installMissingPackages() {
        let (missingFormulae, missingCasks) = missing
        let packagesToInstall = missingFormulae.map { id in
            manager.packages.first(where: { $0.id == id && $0.kind == .formula }) ??
                BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: .formula)
        } + missingCasks.map { id in
            manager.packages.first(where: { $0.id == id && $0.kind == .cask }) ??
                BrewStorePackage(id: id, name: id, description: "", homepage: "", version: "", kind: .cask)
        }

        guard !packagesToInstall.isEmpty else { return }

        BrewStoreActionReviewCoordinator.shared.requestInstall(
            packages: packagesToInstall,
            manager: manager,
            onConfirm: {
                manager.batchPerform(packages: packagesToInstall, action: .install)
            }
        )
    }
}

private struct FlowChipsView: View {
    let items: [String]
    let installedIDs: Set<String>
    let isCask: Bool
    @ObservedObject var manager: HomebrewManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    let resolvedPackage = manager.packages.first { $0.id == item && $0.kind == (isCask ? .cask : .formula) } ?? BrewStorePackage(
                        id: item,
                        name: item,
                        description: "",
                        homepage: "",
                        version: "",
                        kind: isCask ? .cask : .formula,
                        isInstalled: installedIDs.contains(item)
                    )
                    let isInstalled = resolvedPackage.isInstalled

                    HStack(spacing: 4) {
                        Image(systemName: isCask ? "app.fill" : "terminal.fill")
                            .font(.system(size: 9))
                        Text(item)
                            .font(.caption2.monospaced())
                        if isInstalled {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8).bold())
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isInstalled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(isInstalled ? Color.green : Color.primary)
                    .brewStorePackageContextMenu(package: resolvedPackage, manager: manager)
                }
            }
        }
    }
}

private struct NewStackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String, String, [String], [String]) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var formulaeText = ""
    @State private var casksText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Custom Bundle").font(.title2.bold())
            Text("Group your favorite Free & Open-Source packages into a 1-click installation bundle.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Bundle Name (e.g. My Security Audit Kit)", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Formulae (comma-separated CLI IDs)").font(.caption.bold())
                TextField("e.g. fzf, ripgrep, bat, mole", text: $formulaeText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Casks (comma-separated GUI App IDs)").font(.caption.bold())
                TextField("e.g. ghostty, zed, raycast, bitwarden", text: $casksText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Create Bundle") {
                    let formulae = formulaeText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    let casks = casksText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    onCreate(name, description, "shippingbox.fill", formulae, casks)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 480)
    }
}
