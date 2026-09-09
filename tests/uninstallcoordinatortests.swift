@testable import BrewStore
import XCTest

@MainActor
final class UninstallCoordinatorTests: XCTestCase {
    private func package(
        id: String,
        installed: Bool = true,
        dependencies: [String] = []
    ) -> BrewStorePackage {
        BrewStorePackage(
            id: id,
            name: id.capitalized,
            description: "",
            homepage: "",
            version: "1.0",
            kind: .formula,
            isInstalled: installed,
            dependencies: dependencies
        )
    }

    func testRequestOnlyPreviewsAndDoesNotExecuteBeforeConfirmation() {
        var executedPackages: [BrewStorePackage] = []
        var completionResult: Bool?
        let coordinator = BrewStoreUninstallCoordinator { _, packages in
            executedPackages = packages
        }
        let manager = HomebrewManager()
        let target = package(id: "target")

        coordinator.requestUninstall(package: target, manager: manager) { succeeded in
            completionResult = succeeded
        }

        XCTAssertNotNil(coordinator.pendingRequest)
        XCTAssertTrue(executedPackages.isEmpty)

        coordinator.cancel()

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertTrue(executedPackages.isEmpty)
        XCTAssertEqual(completionResult, false)
    }

    func testConfirmRoutesASelectedBatchOnlyAfterPreview() {
        var executedPackages: [BrewStorePackage] = []
        let coordinator = BrewStoreUninstallCoordinator { _, packages in
            executedPackages = packages
        }
        let manager = HomebrewManager()
        let first = package(id: "first")
        let second = package(id: "second")

        coordinator.requestUninstall(packages: [first, second], manager: manager)
        XCTAssertTrue(executedPackages.isEmpty)

        coordinator.confirm()

        XCTAssertEqual(executedPackages.map(\.id), ["first", "second"])
        XCTAssertNil(coordinator.pendingRequest)
    }

    func testRequestRejectsPackagesThatAreNotInstalled() {
        var didExecute = false
        let coordinator = BrewStoreUninstallCoordinator { _, _ in
            didExecute = true
        }
        let manager = HomebrewManager()
        let available = package(id: "available", installed: false)

        coordinator.requestUninstall(package: available, manager: manager)

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertFalse(didExecute)
    }

    func testPreviewAggregatesDependencyImpactWarnings() {
        let foundation = package(id: "foundation", installed: true)
        let dependent = package(id: "dependent", dependencies: ["foundation"])

        let impacts = BrewStoreUninstallCoordinator.dependencyImpacts(
            for: [foundation],
            in: [foundation, dependent]
        )

        XCTAssertEqual(impacts.count, 1)
        XCTAssertTrue(impacts[0].isDestructive)
        XCTAssertEqual(impacts[0].brokenDownstreamPackages, ["Dependent"])
    }

    func testAutoremoveUsesTheSamePendingPreviewGate() {
        var didExecute = false
        let coordinator = BrewStoreUninstallCoordinator(executeAutoremove: { _ in
            didExecute = true
        })
        let manager = HomebrewManager()

        coordinator.requestAutoremove(manager: manager)

        XCTAssertNotNil(coordinator.pendingRequest)
        XCTAssertFalse(didExecute)

        coordinator.confirm()

        XCTAssertTrue(didExecute)
        XCTAssertNil(coordinator.pendingRequest)
    }
}
