@testable import BrewStore
import XCTest

@MainActor
final class PackagePinningSynchronizationTests: XCTestCase {
    private func makeMockManager(packages: [BrewStorePackage]) -> HomebrewManager {
        let manager = HomebrewManager()
        manager.packages = packages
        manager.brewPath = "/opt/homebrew/bin/brew"
        return manager
    }

    func testPinningSuccessSynchronizesPinningManagerAndPackageState() async {
        let package = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Fast line search",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: true,
            isPinned: false
        )
        let manager = makeMockManager(packages: [package])

        let mockExecutor = BrewStoreCommandExecutor { _, arguments, _, category, _, _, _ in
            XCTAssertEqual(arguments, ["pin", "ripgrep"])
            return BrewStoreCommandResult(
                standardOutput: "Pinned ripgrep",
                standardError: "",
                terminationStatus: 0,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: category,
                launchErrorDescription: nil
            )
        }

        let pinningManager = BrewStorePackagePinningManager(executor: mockExecutor)
        let succeeded = await pinningManager.pinAsync(packageID: "ripgrep", kind: .formula, manager: manager)

        XCTAssertTrue(succeeded)
        XCTAssertTrue(pinningManager.isPinned(packageID: "ripgrep"))
        XCTAssertTrue(manager.packages.first(where: { $0.id == "ripgrep" })?.isPinned == true)
        XCTAssertFalse(pinningManager.isPinningInProgress(packageID: "ripgrep"))
    }

    func testPinningCommandFailureRollsBackOptimisticState() async {
        let package = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Fast line search",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: true,
            isPinned: false
        )
        let manager = makeMockManager(packages: [package])

        let mockExecutor = BrewStoreCommandExecutor { _, _, _, category, _, _, _ in
            BrewStoreCommandResult(
                standardOutput: "",
                standardError: "Error: No such keg",
                terminationStatus: 1,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: category,
                launchErrorDescription: nil
            )
        }

        let pinningManager = BrewStorePackagePinningManager(executor: mockExecutor)
        let succeeded = await pinningManager.pinAsync(packageID: "ripgrep", kind: .formula, manager: manager)

        XCTAssertFalse(succeeded)
        // Must be rolled back to unpinned
        XCTAssertFalse(pinningManager.isPinned(packageID: "ripgrep"))
        XCTAssertFalse(manager.packages.first(where: { $0.id == "ripgrep" })?.isPinned == true)
        XCTAssertFalse(pinningManager.isPinningInProgress(packageID: "ripgrep"))
        XCTAssertNotNil(manager.errorMessage)
    }

    func testUnpinningSuccessSynchronizesPinningManagerAndPackageState() async {
        let package = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Fast line search",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: true,
            isPinned: true
        )
        let manager = makeMockManager(packages: [package])

        let mockExecutor = BrewStoreCommandExecutor { _, arguments, _, category, _, _, _ in
            XCTAssertEqual(arguments, ["unpin", "ripgrep"])
            return BrewStoreCommandResult(
                standardOutput: "Unpinned ripgrep",
                standardError: "",
                terminationStatus: 0,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: category,
                launchErrorDescription: nil
            )
        }

        let pinningManager = BrewStorePackagePinningManager(executor: mockExecutor)
        pinningManager.pinnedPackageIDs.insert("ripgrep")

        let succeeded = await pinningManager.unpinAsync(packageID: "ripgrep", kind: .formula, manager: manager)

        XCTAssertTrue(succeeded)
        XCTAssertFalse(pinningManager.isPinned(packageID: "ripgrep"))
        XCTAssertFalse(manager.packages.first(where: { $0.id == "ripgrep" })?.isPinned == true)
        XCTAssertFalse(pinningManager.isPinningInProgress(packageID: "ripgrep"))
    }

    func testUnpinningCommandFailureRollsBackOptimisticState() async {
        let package = BrewStorePackage(
            id: "ripgrep",
            name: "ripgrep",
            description: "Fast line search",
            homepage: "https://github.com/BurntSushi/ripgrep",
            version: "14.1.0",
            kind: .formula,
            isInstalled: true,
            isPinned: true
        )
        let manager = makeMockManager(packages: [package])

        let mockExecutor = BrewStoreCommandExecutor { _, _, _, category, _, _, _ in
            BrewStoreCommandResult(
                standardOutput: "",
                standardError: "Error: Operation not permitted",
                terminationStatus: 1,
                wasTerminated: false,
                didTimeOut: false,
                wasCancelled: false,
                standardOutputWasTruncated: false,
                standardErrorWasTruncated: false,
                category: category,
                launchErrorDescription: nil
            )
        }

        let pinningManager = BrewStorePackagePinningManager(executor: mockExecutor)
        pinningManager.pinnedPackageIDs.insert("ripgrep")

        let succeeded = await pinningManager.unpinAsync(packageID: "ripgrep", kind: .formula, manager: manager)

        XCTAssertFalse(succeeded)
        // Must be rolled back to pinned
        XCTAssertTrue(pinningManager.isPinned(packageID: "ripgrep"))
        XCTAssertTrue(manager.packages.first(where: { $0.id == "ripgrep" })?.isPinned == true)
        XCTAssertFalse(pinningManager.isPinningInProgress(packageID: "ripgrep"))
        XCTAssertNotNil(manager.errorMessage)
    }

    func testInProgressStateAndIdempotentPinning() {
        let manager = makeMockManager(packages: [])
        let pinningManager = BrewStorePackagePinningManager()

        pinningManager.inProgressPackageIDs.insert("ripgrep")
        XCTAssertTrue(pinningManager.isPinningInProgress(packageID: "ripgrep"))
        pinningManager.inProgressPackageIDs.remove("ripgrep")
        XCTAssertFalse(pinningManager.isPinningInProgress(packageID: "ripgrep"))

        // Already pinned package rejects duplicate pin
        pinningManager.pinnedPackageIDs.insert("ripgrep")
        pinningManager.pin(packageID: "ripgrep", kind: .formula, manager: manager)
        XCTAssertTrue(pinningManager.isPinned(packageID: "ripgrep"))

        // Already unpinned package rejects duplicate unpin
        pinningManager.pinnedPackageIDs.remove("ripgrep")
        pinningManager.unpin(packageID: "ripgrep", kind: .formula, manager: manager)
        XCTAssertFalse(pinningManager.isPinned(packageID: "ripgrep"))
    }

    func testPackageFilterEngineConsidersPinningManager() {
        let pkg = BrewStorePackage(
            id: "neovim",
            name: "neovim",
            description: "",
            homepage: "",
            version: "0.10.0",
            kind: .formula,
            isInstalled: true,
            isPinned: false
        )

        BrewStorePackagePinningManager.shared.pinnedPackageIDs.insert("neovim")
        defer {
            BrewStorePackagePinningManager.shared.pinnedPackageIDs.remove("neovim")
        }

        let filtered = BrewStorePackageFilterEngine.filterAndSort(
            packages: [pkg],
            query: "",
            kind: nil,
            tap: "All Taps",
            pinnedOnly: true,
            updatesOnly: false,
            license: .all,
            editorial: .all,
            sort: .nameAsc,
            pinnedIDs: BrewStorePackagePinningManager.shared.pinnedPackageIDs
        )

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.id, "neovim")
    }
}
