import XCTest
@testable import BrewStore

@MainActor
final class WorkspaceManagerTests: XCTestCase {

    func testBuiltInTemplatesExist() {
        let manager = BrewStoreWorkspaceManager()
        let templates = manager.profiles.filter(\.isBuiltIn)
        XCTAssertGreaterThanOrEqual(templates.count, 4)

        let ids = templates.map(\.id)
        XCTAssertTrue(ids.contains("fullstack_web"))
        XCTAssertTrue(ids.contains("ai_datascience"))
        XCTAssertTrue(ids.contains("systems_rust"))
        XCTAssertTrue(ids.contains("devops_cloud"))
    }

    func testAddAndRemoveCustomProfile() {
        let manager = BrewStoreWorkspaceManager()
        let customID = "test_profile_\(UUID().uuidString)"
        let profile = BrewStoreWorkspaceProfile(
            id: customID,
            name: "Test Profile",
            description: "A test environment",
            icon: "hammer.fill",
            accentColor: "blue",
            versionLinks: ["node": "node@22"],
            servicesToStart: ["redis"],
            servicesToStop: [],
            requiredPackages: ["node@22"],
            isBuiltIn: false
        )

        manager.addProfile(profile)
        XCTAssertTrue(manager.profiles.contains(where: { $0.id == customID }))

        manager.deleteProfile(id: customID)
        XCTAssertFalse(manager.profiles.contains(where: { $0.id == customID }))
    }

    func testCannotDeleteBuiltInProfile() {
        let manager = BrewStoreWorkspaceManager()
        manager.deleteProfile(id: "fullstack_web")
        XCTAssertTrue(manager.profiles.contains(where: { $0.id == "fullstack_web" }))
    }

    func testDeactivateWorkspace() {
        let manager = BrewStoreWorkspaceManager()
        manager.activeProfileID = "fullstack_web"
        XCTAssertEqual(manager.activeProfile?.id, "fullstack_web")

        manager.deactivateCurrentWorkspace()
        XCTAssertNil(manager.activeProfileID)
        XCTAssertNil(manager.activeProfile)
    }
}
