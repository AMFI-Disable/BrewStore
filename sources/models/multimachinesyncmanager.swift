import Foundation

struct MacMachineProfile: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let arch: String
    let timestamp: Date
    let formulae: [String]
    let casks: [String]
    let taps: [String]

    var totalPackagesCount: Int {
        formulae.count + casks.count
    }
}

struct CrossMacDiffReport: Hashable, Codable {
    let localMachine: String
    let remoteMachine: String
    let missingOnLocalFormulae: [String]
    let missingOnLocalCasks: [String]
    let missingOnRemoteFormulae: [String]
    let missingOnRemoteCasks: [String]
    let commonCount: Int

    var totalMissingOnLocal: Int {
        missingOnLocalFormulae.count + missingOnLocalCasks.count
    }
}

@MainActor
final class BrewStoreMultiMachineSyncManager: ObservableObject {
    static let shared = BrewStoreMultiMachineSyncManager()

    private let profilesKey = "BrewStore.MultiMachineProfiles"

    @Published var savedProfiles: [MacMachineProfile] = []
    @Published var activeDiff: CrossMacDiffReport?

    init() {
        loadSavedProfiles()
    }

    func loadSavedProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([MacMachineProfile].self, from: data) {
            self.savedProfiles = decoded
        }
    }

    func saveProfile(_ profile: MacMachineProfile) {
        var existing = savedProfiles.filter { $0.id != profile.id }
        existing.append(profile)
        self.savedProfiles = existing
        if let encoded = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }

    func deleteProfile(id: String) {
        let updated = savedProfiles.filter { $0.id != id }
        self.savedProfiles = updated
        if let encoded = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }

    func createCurrentMachineProfile(manager: HomebrewManager, name: String) -> MacMachineProfile {
        let installed = manager.packages.filter(\.isInstalled)
        let formulae = installed.filter { $0.kind == .formula }.map(\.id)
        let casks = installed.filter { $0.kind == .cask }.map(\.id)
        let taps = manager.taps.map(\.name)

        #if arch(arm64)
            let arch = "Apple Silicon (arm64)"
        #else
            let arch = "Intel (x86_64)"
        #endif

        let profile = MacMachineProfile(
            id: UUID().uuidString,
            name: name.isEmpty ? Host.current().localizedName ?? "My Mac" : name,
            arch: arch,
            timestamp: Date(),
            formulae: formulae,
            casks: casks,
            taps: taps
        )
        saveProfile(profile)
        return profile
    }

    func computeDiff(local: MacMachineProfile, remote: MacMachineProfile) -> CrossMacDiffReport {
        let localFormulaeSet = Set(local.formulae)
        let localCasksSet = Set(local.casks)
        let remoteFormulaeSet = Set(remote.formulae)
        let remoteCasksSet = Set(remote.casks)

        let missingOnLocalFormulae = Array(remoteFormulaeSet.subtracting(localFormulaeSet)).sorted()
        let missingOnLocalCasks = Array(remoteCasksSet.subtracting(localCasksSet)).sorted()
        let missingOnRemoteFormulae = Array(localFormulaeSet.subtracting(remoteFormulaeSet)).sorted()
        let missingOnRemoteCasks = Array(localCasksSet.subtracting(remoteCasksSet)).sorted()

        let commonFormulae = localFormulaeSet.intersection(remoteFormulaeSet).count
        let commonCasks = localCasksSet.intersection(remoteCasksSet).count

        let diff = CrossMacDiffReport(
            localMachine: local.name,
            remoteMachine: remote.name,
            missingOnLocalFormulae: missingOnLocalFormulae,
            missingOnLocalCasks: missingOnLocalCasks,
            missingOnRemoteFormulae: missingOnRemoteFormulae,
            missingOnRemoteCasks: missingOnRemoteCasks,
            commonCount: commonFormulae + commonCasks
        )
        self.activeDiff = diff
        return diff
    }
}
