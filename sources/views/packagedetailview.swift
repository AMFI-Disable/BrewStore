import SwiftUI
import JuicerKit

struct PackageDetailView: View {
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage
    @State private var removalPlan: RemovalPlan?
    @State private var isScanningRemoval = false
    @State private var removalError: String?
    @State private var showingRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Image(systemName: package.kind == .cask ? "app.fill" : "terminal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(package.name).font(.largeTitle.bold())
                        Text(package.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(package.displayKind).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if !package.description.isEmpty { Text(package.description).font(.body) }
                HStack {
                    Label(package.version.isEmpty ? "Version unavailable" : package.version, systemImage: "number")
                    if package.isInstalled { Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    if package.isOutdated { Label("Update available", systemImage: "arrow.up.circle.fill").foregroundStyle(.orange) }
                }
                .font(.callout)

                HStack {
                    if !package.isInstalled {
                        Button("Install") { manager.perform(package: package, action: .install) }
                            .buttonStyle(.borderedProminent)
                    } else if package.isOutdated {
                        Button("Upgrade") { manager.perform(package: package, action: .upgrade) }
                            .buttonStyle(.borderedProminent)
                    }
                    if package.isInstalled && package.kind == .cask {
                        Button("Preview Uninstall", role: .destructive) { scanRemoval() }
                            .disabled(isScanningRemoval || manager.isOperating)
                    } else if package.isInstalled {
                        Button("Uninstall", role: .destructive) { manager.perform(package: package, action: .uninstall) }
                            .disabled(manager.isOperating)
                    }
                    if !package.homepage.isEmpty, let url = URL(string: package.homepage) {
                        Link("Homepage", destination: url)
                    }
                }

                if isScanningRemoval { ProgressView("Scanning for leftovers…") }
                if let removalError { Text(removalError).foregroundStyle(.red).textSelection(.enabled) }
                if !manager.statusMessage.isEmpty { Text(manager.statusMessage).font(.callout).foregroundStyle(.secondary) }
                if let error = manager.errorMessage { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }

                Text("Removal safety")
                    .font(.headline)
                Text("BrewStore removes the Homebrew cask first, then lets you review matching application support files before moving selected items to the Trash. It never deletes leftovers automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
        .sheet(isPresented: $showingRemoval) {
            if let plan = removalPlan {
                RemovalPreviewView(manager: manager, package: package, plan: plan)
            }
        }
    }

    private func scanRemoval() {
        guard let applicationName = package.applicationNames.first else {
            removalError = "Homebrew did not report an application bundle for this cask. Use the standard uninstall action instead."
            return
        }
        isScanningRemoval = true
        removalError = nil
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let candidates = [
            URL(fileURLWithPath: "/Applications").appendingPathComponent(applicationName),
            homeApplications.appendingPathComponent(applicationName)
        ]
        let appURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) ?? candidates[0]
        let bundleID = Bundle(url: appURL)?.bundleIdentifier ?? ""
        let identity = AppIdentity(name: appURL.deletingPathExtension().lastPathComponent, bundleIdentifier: bundleID, applicationURL: appURL)
        Task.detached(priority: .userInitiated) {
            let plan = AppRemovalScanner().scan(application: identity)
            await MainActor.run {
                removalPlan = plan
                isScanningRemoval = false
                if plan.candidates.isEmpty { removalError = "No matching application bundle or support files were found." }
                else { showingRemoval = true }
            }
        }
    }
}

private struct RemovalPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: HomebrewManager
    let package: BrewStorePackage
    @State var plan: RemovalPlan
    @State private var isRunning = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review removal").font(.title.bold())
            Text("BrewStore will uninstall the Homebrew cask, then move only the selected local targets to the Trash.")
                .foregroundStyle(.secondary)
            HStack {
                Label("\(plan.selectedCount) items", systemImage: "doc.on.doc")
                Label(ByteCountFormatter.string(fromByteCount: plan.selectedBytes, countStyle: .file), systemImage: "externaldrive")
            }
            .font(.callout)

            List {
                ForEach($plan.candidates) { $candidate in
                    Toggle(isOn: $candidate.isSelected) {
                        VStack(alignment: .leading) {
                            Text(candidate.url.lastPathComponent)
                            Text("\(candidate.kind.rawValue) · \(candidate.confidence.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let resultMessage { Text(resultMessage).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Uninstall and Move Selected to Trash", role: .destructive) { execute() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || plan.selectedCandidates.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
    }

    private func execute() {
        isRunning = true
        manager.perform(package: package, action: .uninstall) { succeeded in
            guard succeeded else {
                isRunning = false
                resultMessage = "Homebrew could not uninstall the cask; no leftover files were moved."
                return
            }

            let roots = [
                URL(fileURLWithPath: "/Applications"),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
            ]
            let executor = TrashExecutor(validator: PathSafetyValidator(allowedRoots: roots))
            let selectedPlan = plan
            Task.detached(priority: .userInitiated) {
                let result = executor.execute(plan: selectedPlan)
                await MainActor.run {
                    isRunning = false
                    switch result {
                    case .completed(let manifest): resultMessage = "Moved \(manifest.movedURLs.count) selected items to the Trash."
                    case .partiallyCompleted(let manifest): resultMessage = "Moved \(manifest.movedURLs.count) items; \(manifest.failures.count) could not be moved."
                    case .cancelled(let manifest): resultMessage = "Cancelled after moving \(manifest.movedURLs.count) items."
                    case .failed(let reason, _): resultMessage = reason
                    }
                }
            }
        }
    }
}
