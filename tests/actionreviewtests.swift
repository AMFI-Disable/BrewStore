@testable import BrewStore
import XCTest

@MainActor
final class ActionReviewTests: XCTestCase {
    private func makePackage(
        id: String,
        name: String? = nil,
        version: String = "1.0.0",
        installedVersion: String? = nil,
        kind: BrewPackageKind = .formula,
        dependencies: [String] = []
    ) -> BrewStorePackage {
        BrewStorePackage(
            id: id,
            name: name ?? id.capitalized,
            description: "Test description for \(id)",
            homepage: "https://example.com/\(id)",
            version: version,
            kind: kind,
            isInstalled: installedVersion != nil,
            dependencies: dependencies,
            installedVersion: installedVersion
        )
    }

    func testDirectInstallReviewLifecycle() {
        let coordinator = BrewStoreActionReviewCoordinator()
        let manager = HomebrewManager()
        let pkg = makePackage(id: "ffmpeg", name: "FFmpeg", version: "6.1.1", kind: .formula, dependencies: ["openssl@3", "x264"])

        var confirmed = false
        coordinator.requestInstall(package: pkg, manager: manager) {
            confirmed = true
        }

        guard let request = coordinator.pendingReview else {
            XCTFail("Expected pending review request")
            return
        }

        XCTAssertEqual(request.title, "Review Installation")
        XCTAssertEqual(request.items.count, 1)
        XCTAssertEqual(request.items.first?.title, "FFmpeg")
        XCTAssertEqual(request.items.first?.command, "brew install ffmpeg")
        XCTAssertFalse(request.isDestructive)
        XCTAssertFalse(confirmed)

        // Confirm
        coordinator.confirm()
        XCTAssertTrue(confirmed)
        XCTAssertNil(coordinator.pendingReview)
    }

    func testBatchUpgradeReviewLifecycle() {
        let coordinator = BrewStoreActionReviewCoordinator()
        let manager = HomebrewManager()
        let pkgs = [
            makePackage(id: "git", name: "Git", version: "2.44.0", installedVersion: "2.43.0", kind: .formula),
            makePackage(id: "vlc", name: "VLC", version: "3.0.20", installedVersion: "3.0.19", kind: .cask)
        ]

        var confirmed = false
        coordinator.requestUpgrade(packages: pkgs, manager: manager) {
            confirmed = true
        }

        guard let request = coordinator.pendingReview else {
            XCTFail("Expected pending review request")
            return
        }

        XCTAssertEqual(request.title, "Review Batch Update")
        XCTAssertEqual(request.confirmationTitle, "Upgrade 2 Packages")
        XCTAssertEqual(request.items.count, 2)
        XCTAssertEqual(request.commandPreview, "brew upgrade git vlc")
        XCTAssertFalse(confirmed)

        // Cancel
        coordinator.cancel()
        XCTAssertFalse(confirmed)
        XCTAssertNil(coordinator.pendingReview)
    }

    func testBrewfileImportReview() {
        let coordinator = BrewStoreActionReviewCoordinator()
        let entries = [
            ImportedBrewfileEntry(
                id: "ripgrep",
                rawName: "ripgrep",
                kind: .formula,
                matchedPackage: makePackage(id: "ripgrep", name: "ripgrep"),
                isInstalled: false,
                isOutdated: false,
                isSelected: true
            ),
            ImportedBrewfileEntry(
                id: "google-chrome",
                rawName: "google-chrome",
                kind: .cask,
                matchedPackage: makePackage(id: "google-chrome", name: "Google Chrome", kind: .cask),
                isInstalled: false,
                isOutdated: false,
                isSelected: true
            ),
            ImportedBrewfileEntry(
                id: "wget",
                rawName: "wget",
                kind: .formula,
                matchedPackage: makePackage(id: "wget", name: "wget", installedVersion: "1.21"),
                isInstalled: true,
                isOutdated: false,
                isSelected: true
            )
        ]

        var confirmed = false
        coordinator.requestBrewfileImport(entries: entries, taps: ["homebrew/cask-fonts"]) {
            confirmed = true
        }

        guard let request = coordinator.pendingReview else {
            XCTFail("Expected pending review request")
            return
        }

        XCTAssertEqual(request.title, "Review Brewfile Import")
        // Only missing entries should be listed
        XCTAssertEqual(request.items.count, 2)
        XCTAssertTrue(request.notes.contains { $0.contains("homebrew/cask-fonts") })
        XCTAssertFalse(confirmed)

        coordinator.confirm()
        XCTAssertTrue(confirmed)
        XCTAssertNil(coordinator.pendingReview)
    }

    func testSettingsResetReview() {
        let coordinator = BrewStoreActionReviewCoordinator()
        let options: Set<BrewStoreResetOption> = [.unpinEverything, .untapEverything]

        var confirmed = false
        coordinator.requestSettingsReset(options: options) {
            confirmed = true
        }

        guard let request = coordinator.pendingReview else {
            XCTFail("Expected pending review request")
            return
        }

        XCTAssertEqual(request.title, "Review Settings Reset")
        XCTAssertEqual(request.items.count, 2)
        XCTAssertTrue(request.isDestructive) // untapEverything is danger tier
        XCTAssertFalse(confirmed)

        coordinator.confirm()
        XCTAssertTrue(confirmed)
        XCTAssertNil(coordinator.pendingReview)
    }

    func testWishlistCollectionDeleteReview() {
        let coordinator = BrewStoreActionReviewCoordinator()
        let col = BrewStoreCollection(title: "Dev Tools", description: "My dev tools", packageIDs: ["git", "node"], colorName: "blue")

        var confirmed = false
        coordinator.requestWishlistCollectionDelete(collection: col) {
            confirmed = true
        }

        guard let request = coordinator.pendingReview else {
            XCTFail("Expected pending review request")
            return
        }

        XCTAssertEqual(request.title, "Review Collection Deletion")
        XCTAssertEqual(request.confirmationTitle, "Delete Collection")
        XCTAssertTrue(request.isDestructive)
        XCTAssertFalse(confirmed)

        coordinator.confirm()
        XCTAssertTrue(confirmed)
        XCTAssertNil(coordinator.pendingReview)
    }
}
