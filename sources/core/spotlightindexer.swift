import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Manages macOS CoreSpotlight indexing for installed Homebrew packages.
final class BrewStoreSpotlightIndexer: Sendable {
    static let shared = BrewStoreSpotlightIndexer()
    static let domainIdentifier = "com.amfi-disable.brewstore.package"

    private init() {}

    var isSupported: Bool {
        CSSearchableIndex.isIndexingAvailable()
    }

    /// Creates a CSSearchableItem representation of a Homebrew package.
    func createSearchableItem(for package: BrewStorePackage) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
        attributeSet.title = package.name
        attributeSet.contentDescription = package.description.isEmpty ? "\(package.name) (\(package.displayKind))" : package.description
        attributeSet.version = package.installedVersion ?? package.version
        attributeSet.keywords = [
            package.id,
            package.name,
            package.kind.rawValue,
            "Homebrew",
            package.tap ?? "homebrew/core"
        ]

        if let url = URL(string: package.homepage) {
            attributeSet.url = url
        }

        return CSSearchableItem(
            uniqueIdentifier: "brewstore://package/\(package.id)",
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributeSet
        )
    }

    /// Indexes the provided list of packages into macOS Spotlight.
    func indexInstalledPackages(_ packages: [BrewStorePackage]) {
        guard isSupported else { return }

        let installed = packages.filter(\.isInstalled)
        let items = installed.map { createSearchableItem(for: $0) }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                #if DEBUG
                    print("[SpotlightIndexer] Failed to index items: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Removes a specific package from the Spotlight index.
    func removePackageFromIndex(packageID: String) {
        guard isSupported else { return }
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ["brewstore://package/\(packageID)"]) { _ in }
    }

    /// Deletes all indexed packages under the domain.
    func clearAllDomainIndices() {
        guard isSupported else { return }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { _ in }
    }
}
