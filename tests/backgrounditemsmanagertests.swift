@testable import BrewStore
import XCTest

@MainActor
final class BackgroundItemsManagerTests: XCTestCase {
    func testDeduceAppNameFromLabelsAndPaths() {
        let name1 = BrewStoreBackgroundItemsManager.deduceAppName(
            from: "com.google.keystone.agent",
            programPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        )
        XCTAssertEqual(name1, "Google Chrome")

        let name2 = BrewStoreBackgroundItemsManager.deduceAppName(
            from: "com.docker.helper",
            programPath: nil
        )
        XCTAssertEqual(name2, "Docker Desktop")

        let name3 = BrewStoreBackgroundItemsManager.deduceAppName(
            from: "com.spotify.client.startuphelper",
            programPath: nil
        )
        XCTAssertEqual(name3, "Spotify")
    }

    func testDeduceFriendlyName() {
        let friendly1 = BrewStoreBackgroundItemsManager.deduceFriendlyName(
            from: "com.google.keystone.agent",
            appName: "Google Chrome",
            filename: "com.google.keystone.agent.plist"
        )
        XCTAssertEqual(friendly1, "Google Chrome (Agent)")

        let friendly2 = BrewStoreBackgroundItemsManager.deduceFriendlyName(
            from: "com.custom.daemon",
            appName: nil,
            filename: "com.custom.daemon.plist"
        )
        XCTAssertEqual(friendly2, "Daemon")
    }

    func testBackgroundItemDisplayNameFallback() {
        let item1 = BrewStoreBackgroundItem(
            id: "1",
            name: "Docker Helper",
            label: "com.docker.helper",
            programPath: nil,
            plistURL: nil,
            kind: .userLaunchAgent,
            associatedAppName: "Docker Desktop",
            isLoaded: true,
            isRunning: true,
            runAtLoad: true,
            pid: 1234
        )
        XCTAssertEqual(item1.displayName, "Docker Helper")

        let item2 = BrewStoreBackgroundItem(
            id: "2",
            name: "com.random.agent",
            label: "com.random.agent",
            programPath: nil,
            plistURL: nil,
            kind: .userLaunchAgent,
            associatedAppName: "RandomApp",
            isLoaded: false,
            isRunning: false,
            runAtLoad: false,
            pid: nil
        )
        XCTAssertEqual(item2.displayName, "RandomApp Helper")
    }
}
