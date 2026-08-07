import XCTest
@testable import BrewStore

final class HomebrewJSONParserTests: XCTestCase {
    func testParsesCaskAndApplicationArtifact() throws {
        let data = #"{"casks":[{"token":"example","name":["Example"],"desc":"An example app","homepage":"https://example.com","version":"1.2.3","artifacts":[{"app":["Example.app"]}]}]}"#.data(using: .utf8)!
        let packages = HomebrewJSONParser.packages(from: data, kind: .cask, installedIDs: ["example"], outdatedIDs: ["example"])
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].id, "example")
        XCTAssertEqual(packages[0].applicationNames, ["Example.app"])
        XCTAssertTrue(packages[0].isInstalled)
        XCTAssertTrue(packages[0].isOutdated)
    }

    func testRejectsMalformedJSON() {
        XCTAssertTrue(HomebrewJSONParser.packages(from: Data("bad".utf8), kind: .formula, installedIDs: [], outdatedIDs: []).isEmpty)
    }

    func testParsesServicesAndTaps() {
        let services = HomebrewJSONParser.services(from: Data(#"[{"name":"redis","status":"started","user":"even","file":"/tmp/redis.plist"}]"#.utf8))
        XCTAssertEqual(services.first?.status, "started")
        XCTAssertEqual(HomebrewJSONParser.taps(from: "homebrew/cask\nuser/tools\n").map(\.name), ["homebrew/cask", "user/tools"])
    }
}
