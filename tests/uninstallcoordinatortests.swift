import AppKit
@testable import BrewStore
import XCTest

@MainActor
final class UninstallCoordinatorTests: XCTestCase {
    private func package(
        id: String,
        installed: Bool = true,
        kind: BrewPackageKind = .formula,
        dependencies: [String] = []
    ) -> BrewStorePackage {
        BrewStorePackage(
            id: id,
            name: id.capitalized,
            description: "",
            homepage: "",
            version: "1.0",
            kind: kind,
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

    func testConfirmTrashesSelectedResidualCandidates() {
        var trashedPlans: [BrewStoreRemovalPlan] = []
        var executedPackages: [BrewStorePackage] = []

        let coordinator = BrewStoreUninstallCoordinator(
            executeUninstall: { _, pkgs in
                executedPackages = pkgs
            },
            executeTrash: { plan in
                trashedPlans.append(plan)
                let manifest = BrewStoreRemovalManifest(
                    id: UUID(),
                    planID: plan.id,
                    application: plan.application,
                    movedURLs: plan.selectedCandidates.map(\.url),
                    failures: [],
                    createdAt: Date()
                )
                return .completed(manifest: manifest)
            }
        )

        let manager = HomebrewManager()
        let caskPkg = package(id: "testapp", installed: true, kind: .cask)
        coordinator.requestUninstall(package: caskPkg, manager: manager)

        guard var request = coordinator.pendingRequest else {
            XCTFail("Pending request must not be nil")
            return
        }

        let fakeURL1 = URL(fileURLWithPath: "/tmp/testapp/Library/Caches")
        let fakeURL2 = URL(fileURLWithPath: "/tmp/testapp/Library/Logs")
        let identity = BrewStoreAppIdentity(name: "TestApp", bundleIdentifier: "com.test.app", applicationURL: URL(fileURLWithPath: "/Applications/TestApp.app"))
        let candidates = [
            BrewStoreRemovalCandidate(url: fakeURL1, kind: .cache, size: 1024, confidence: .exactBundleIdentifier, isSelected: true),
            BrewStoreRemovalCandidate(url: fakeURL2, kind: .log, size: 2048, confidence: .exactBundleIdentifier, isSelected: false)
        ]
        let plan = BrewStoreRemovalPlan(application: identity, candidates: candidates)
        request.removalPlans = [plan]
        coordinator.pendingRequest = request

        XCTAssertEqual(coordinator.pendingRequest?.totalResidualBytes, 1024)
        XCTAssertTrue(coordinator.pendingRequest?.hasResiduals == true)

        // Confirm with specific selection
        coordinator.confirm(selectedResidualURLs: [fakeURL1])

        XCTAssertEqual(executedPackages.map(\.id), ["testapp"])
        XCTAssertEqual(trashedPlans.count, 1)
        XCTAssertEqual(trashedPlans.first?.selectedCandidates.map(\.url), [fakeURL1])
        XCTAssertNil(coordinator.pendingRequest)
    }

    func testCandidateKindMetadata() {
        XCTAssertEqual(BrewStoreRemovalCandidateKind.cache.displayName, "Caches & Data")
        XCTAssertEqual(BrewStoreRemovalCandidateKind.applicationSupport.displayName, "Application Support")
        XCTAssertEqual(BrewStoreRemovalCandidateKind.preference.displayName, "Preferences")
        XCTAssertEqual(BrewStoreRemovalCandidateKind.cache.systemImage, "internaldrive")
        XCTAssertEqual(BrewStoreRemovalCandidateKind.applicationSupport.systemImage, "folder.fill.badge.gear")
    }
}
