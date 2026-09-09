import AppKit
import Foundation

@MainActor
final class BrewStorePackagePinningManager: ObservableObject {
    static let shared = BrewStorePackagePinningManager()

    private let pinnedStorageKey = "BrewStore.PinnedPackages"

    @Published var pinnedPackageIDs: Set<String> = []
    @Published var inProgressPackageIDs: Set<String> = []
    @Published var lastPinMessage: String?

    private var pendingOperationIDs: [String: UUID] = [:]

    var executor: BrewStoreCommandExecutor

    init(executor: BrewStoreCommandExecutor = .shared) {
        self.executor = executor
        loadPinnedPackages()
    }

    func loadPinnedPackages() {
        if let array = UserDefaults.standard.stringArray(forKey: pinnedStorageKey) {
            self.pinnedPackageIDs = Set(array.map { $0.lowercased() })
        }
    }

    private func savePinned() {
        UserDefaults.standard.set(Array(pinnedPackageIDs), forKey: pinnedStorageKey)
    }

    func isPinned(packageID: String) -> Bool {
        pinnedPackageIDs.contains(packageID.lowercased())
    }

    func isPinningInProgress(packageID: String) -> Bool {
        inProgressPackageIDs.contains(packageID.lowercased())
    }

    func togglePin(package: BrewStorePackage, manager: HomebrewManager) {
        if isPinned(packageID: package.id) {
            unpin(packageID: package.id, kind: package.kind, manager: manager)
        } else {
            pin(packageID: package.id, kind: package.kind, manager: manager)
        }
    }

    func pin(packageID: String, kind: BrewPackageKind = .formula, manager: HomebrewManager) {
        let lower = packageID.lowercased()
        guard !isPinned(packageID: lower) else { return }

        let opID = UUID()
        pendingOperationIDs[lower] = opID
        inProgressPackageIDs.insert(lower)
        pinnedPackageIDs.insert(lower)
        manager.setPackagePinned(packageID: lower, isPinned: true)
        savePinned()
        lastPinMessage = "Pinned \(packageID)"

        // If cask, local pinning is complete
        guard kind == .formula else {
            inProgressPackageIDs.remove(lower)
            pendingOperationIDs.removeValue(forKey: lower)
            return
        }

        guard let brewPath = manager.brewPath else {
            inProgressPackageIDs.remove(lower)
            pendingOperationIDs.removeValue(forKey: lower)
            return
        }

        let exec = self.executor
        Task.detached(priority: .userInitiated) {
            let result = exec.run(
                executablePath: brewPath,
                arguments: ["pin", packageID],
                timeout: 30,
                category: .reversibleMutation
            )
            await MainActor.run {
                guard self.pendingOperationIDs[lower] == opID else { return }
                self.pendingOperationIDs.removeValue(forKey: lower)
                self.inProgressPackageIDs.remove(lower)
                if !result.succeeded {
                    // Revert optimistic state if brew CLI pin command failed
                    self.pinnedPackageIDs.remove(lower)
                    manager.setPackagePinned(packageID: lower, isPinned: false)
                    self.savePinned()
                    let errorOutput = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    manager.errorMessage = errorOutput.isEmpty ? "Failed to pin \(packageID)." : "Failed to pin \(packageID): \(errorOutput)"
                    self.lastPinMessage = "Pin failed: \(errorOutput)"
                }
            }
        }
    }

    @discardableResult
    func pinAsync(packageID: String, kind: BrewPackageKind = .formula, manager: HomebrewManager) async -> Bool {
        let lower = packageID.lowercased()
        guard !isPinned(packageID: lower) else { return true }

        let opID = UUID()
        pendingOperationIDs[lower] = opID
        inProgressPackageIDs.insert(lower)
        pinnedPackageIDs.insert(lower)
        manager.setPackagePinned(packageID: lower, isPinned: true)
        savePinned()
        lastPinMessage = "Pinned \(packageID)"

        guard kind == .formula else {
            inProgressPackageIDs.remove(lower)
            pendingOperationIDs.removeValue(forKey: lower)
            return true
        }

        guard let brewPath = manager.brewPath else {
            inProgressPackageIDs.remove(lower)
            pendingOperationIDs.removeValue(forKey: lower)
            return true
        }

        let exec = self.executor
        let result = await Task.detached(priority: .userInitiated) {
            exec.run(
                executablePath: brewPath,
                arguments: ["pin", packageID],
                timeout: 30,
                category: .reversibleMutation
            )
        }.value

        guard self.pendingOperationIDs[lower] == opID else { return true }
        self.pendingOperationIDs.removeValue(forKey: lower)
        inProgressPackageIDs.remove(lower)
        if !result.succeeded {
            pinnedPackageIDs.remove(lower)
            manager.setPackagePinned(packageID: lower, isPinned: false)
            savePinned()
            let errorOutput = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            manager.errorMessage = errorOutput.isEmpty ? "Failed to pin \(packageID)." : "Failed to pin \(packageID): \(errorOutput)"
            lastPinMessage = "Pin failed: \(errorOutput)"
            return false
        }
        return true
    }

    func unpin(packageID: String, kind: BrewPackageKind = .formula, manager: HomebrewManager) {
        let lower = packageID.lowercased()
        guard isPinned(packageID: lower) else { return }

        let opID = UUID()
        pendingOperationIDs[lower] = opID
        inProgressPackageIDs.insert(lower)
        pinnedPackageIDs.remove(lower)
        manager.setPackagePinned(packageID: lower, isPinned: false)
        savePinned()
        lastPinMessage = "Unpinned \(packageID)"

        // If cask, local unpinning is complete
        guard kind == .formula else {
            inProgressPackageIDs.remove(lower)
            pendingOperationIDs.removeValue(forKey: lower)
            return
        }

        guard let brewPath = manager.brewPath else {
            inProgressPackageIDs.remove(lower)
            pendingOperationIDs.removeValue(forKey: lower)
            return
        }

        let exec = self.executor
        Task.detached(priority: .userInitiated) {
            let result = exec.run(
                executablePath: brewPath,
                arguments: ["unpin", packageID],
                timeout: 30,
                category: .reversibleMutation
            )
            await MainActor.run {
                guard self.pendingOperationIDs[lower] == opID else { return }
                self.pendingOperationIDs.removeValue(forKey: lower)
                self.inProgressPackageIDs.remove(lower)
                if !result.succeeded {
                    // Revert optimistic removal if brew CLI unpin command failed
                    self.pinnedPackageIDs.insert(lower)
                    manager.setPackagePinned(packageID: lower, isPinned: true)
                    self.savePinned()
                    let errorOutput = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                    manager.errorMessage = errorOutput.isEmpty ? "Failed to unpin \(packageID)." : "Failed to unpin \(packageID): \(errorOutput)"
                    self.lastPinMessage = "Unpin failed: \(errorOutput)"
                }
            }
        }
    }

    @discardableResult
    func unpinAsync(packageID: String, kind: BrewPackageKind = .formula, manager: HomebrewManager) async -> Bool {
        let lower = packageID.lowercased()
        guard isPinned(packageID: lower) else { return true }

        let opID = UUID()
        pendingOperationIDs[lower] = opID
        inProgressPackageIDs.insert(lower)
        pinnedPackageIDs.remove(lower)
        manager.setPackagePinned(packageID: lower, isPinned: false)
        savePinned()
        lastPinMessage = "Unpinned \(packageID)"

        guard kind == .formula else {
            inProgressPackageIDs.remove(lower)
            pendingOperationIDs.removeValue(forKey: lower)
            return true
        }

        guard let brewPath = manager.brewPath else {
            inProgressPackageIDs.remove(lower)
            pendingOperationIDs.removeValue(forKey: lower)
            pinnedPackageIDs.insert(lower)
            manager.setPackagePinned(packageID: lower, isPinned: true)
            savePinned()
            manager.errorMessage = "Homebrew executable not found."
            return false
        }

        let exec = self.executor
        let result = await Task.detached(priority: .userInitiated) {
            exec.run(
                executablePath: brewPath,
                arguments: ["unpin", packageID],
                timeout: 30,
                category: .reversibleMutation
            )
        }.value

        guard self.pendingOperationIDs[lower] == opID else { return true }
        self.pendingOperationIDs.removeValue(forKey: lower)
        inProgressPackageIDs.remove(lower)
        if !result.succeeded {
            pinnedPackageIDs.insert(lower)
            manager.setPackagePinned(packageID: lower, isPinned: true)
            savePinned()
            let errorOutput = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            manager.errorMessage = errorOutput.isEmpty ? "Failed to unpin \(packageID)." : "Failed to unpin \(packageID): \(errorOutput)"
            lastPinMessage = "Unpin failed: \(errorOutput)"
            return false
        }
        return true
    }

    func reconcileWithHomebrew(manager: HomebrewManager) {
        guard let brewPath = manager.brewPath else { return }
        let exec = self.executor
        Task.detached(priority: .userInitiated) {
            let result = exec.run(
                executablePath: brewPath,
                arguments: ["list", "--pinned"],
                timeout: 15,
                category: .readOnly
            )
            guard result.succeeded else { return }
            let pinned = HomebrewJSONParser.pinnedIdentifiers(from: result.standardOutput)
            await MainActor.run {
                self.pinnedPackageIDs = Set(pinned.map { $0.lowercased() })
                self.savePinned()
                var updated = manager.packages
                var hasChanges = false
                for idx in updated.indices {
                    let isPinned = self.pinnedPackageIDs.contains(updated[idx].id.lowercased())
                    if updated[idx].isPinned != isPinned {
                        updated[idx].isPinned = isPinned
                        hasChanges = true
                    }
                }
                if hasChanges {
                    manager.packages = updated
                }
            }
        }
    }

    func resetAllPins(manager: HomebrewManager? = nil) {
        let oldPins = pinnedPackageIDs
        pinnedPackageIDs.removeAll()
        inProgressPackageIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: pinnedStorageKey)
        if let manager {
            var updated = manager.packages
            var hasChanges = false
            for idx in updated.indices {
                if updated[idx].isPinned {
                    updated[idx].isPinned = false
                    hasChanges = true
                }
            }
            if hasChanges {
                manager.packages = updated
            }
            if let brewPath = manager.brewPath {
                let exec = self.executor
                for id in oldPins {
                    Task.detached(priority: .userInitiated) {
                        _ = exec.run(
                            executablePath: brewPath,
                            arguments: ["unpin", id],
                            timeout: 20,
                            category: .reversibleMutation
                        )
                    }
                }
            }
        }
    }

    nonisolated static func installedCellarVersions(for packageID: String, prefix: String) -> [String] {
        let cellarPath = (prefix as NSString).appendingPathComponent("Cellar/\(packageID)")
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: cellarPath) else {
            return []
        }

        return contents.filter { item in
            !item.hasPrefix(".") && item != "INSTALL_RECEIPT.json" && item != ".brew"
        }.sorted(by: { $0.localizedStandardCompare($1) == .orderedDescending })
    }

    func switchActiveVersion(packageID: String, version _: String, manager: HomebrewManager) {
        guard let brewPath = manager.brewPath else { return }
        Task.detached(priority: .userInitiated) {
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["unlink", packageID],
                timeout: 30,
                category: .reversibleMutation
            )
            _ = BrewStoreCommandExecutor.shared.run(
                executablePath: brewPath,
                arguments: ["link", "--overwrite", "--force", packageID],
                timeout: 30,
                category: .reversibleMutation
            )
            await MainActor.run {
                manager.refresh()
            }
        }
    }
}
