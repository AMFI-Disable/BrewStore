import Foundation

@MainActor
final class BrewStoreIgnoredUpdatesManager: ObservableObject {
    static let shared = BrewStoreIgnoredUpdatesManager()

    private let ignoredStorageKey = "BrewStore.IgnoredUpdates"

    @Published var ignoredPackageIDs: Set<String> = []

    init() {
        loadIgnoredPackages()
    }

    func loadIgnoredPackages() {
        if let array = UserDefaults.standard.stringArray(forKey: ignoredStorageKey) {
            self.ignoredPackageIDs = Set(array)
        }
    }

    func isIgnored(packageID: String) -> Bool {
        ignoredPackageIDs.contains(packageID.lowercased())
    }

    func toggleIgnore(packageID: String) {
        if isIgnored(packageID: packageID) {
            unignore(packageID: packageID)
        } else {
            ignore(packageID: packageID)
        }
    }

    func ignore(packageID: String) {
        ignoredPackageIDs.insert(packageID.lowercased())
        saveIgnored()
    }

    func unignore(packageID: String) {
        ignoredPackageIDs.remove(packageID.lowercased())
        saveIgnored()
    }

    private func saveIgnored() {
        UserDefaults.standard.set(Array(ignoredPackageIDs), forKey: ignoredStorageKey)
    }
}
