@testable import BrewStore
import Foundation
import XCTest

final class HomebrewSchemaAdapterTests: XCTestCase {
    func testCoerceToString() {
        XCTAssertEqual(HomebrewSchemaAdapter.coerceToString("string-val"), "string-val")
        XCTAssertEqual(HomebrewSchemaAdapter.coerceToString(42), "42")
        XCTAssertEqual(HomebrewSchemaAdapter.coerceToString(["first", "second"]), "first")
        XCTAssertNil(HomebrewSchemaAdapter.coerceToString(nil))
    }

    func testCoerceToStringArray() {
        XCTAssertEqual(HomebrewSchemaAdapter.coerceToStringArray("single"), ["single"])
        XCTAssertEqual(HomebrewSchemaAdapter.coerceToStringArray(["a", "b", "c"]), ["a", "b", "c"])
        XCTAssertEqual(HomebrewSchemaAdapter.coerceToStringArray(nil), [])
    }

    func testResilientlyParsePackagesFromDifferentRoots() {
        // 1. Plain array
        let arrayData = """
        [{"token": "firefox"}]
        """.data(using: .utf8)!
        let list1 = HomebrewSchemaAdapter.resilientlyParsePackages(from: arrayData, kind: .cask)
        XCTAssertEqual(list1.count, 1)
        XCTAssertEqual(list1.first?["token"] as? String, "firefox")

        // 2. Dict with "casks"
        let dictData = """
        {"casks": [{"token": "chrome"}]}
        """.data(using: .utf8)!
        let list2 = HomebrewSchemaAdapter.resilientlyParsePackages(from: dictData, kind: .cask)
        XCTAssertEqual(list2.count, 1)
        XCTAssertEqual(list2.first?["token"] as? String, "chrome")

        // 3. Dict with "formulae"
        let formulaData = """
        {"formulae": [{"name": "curl"}]}
        """.data(using: .utf8)!
        let list3 = HomebrewSchemaAdapter.resilientlyParsePackages(from: formulaData, kind: .formula)
        XCTAssertEqual(list3.count, 1)
        XCTAssertEqual(list3.first?["name"] as? String, "curl")
    }

    func testParseSemanticVersion() {
        let v1 = HomebrewSchemaAdapter.parseSemanticVersion("Homebrew 5.0.7-99-gd61f229")
        XCTAssertEqual(v1?.major, 5)
        XCTAssertEqual(v1?.minor, 0)
        XCTAssertEqual(v1?.patch, 7)

        let v2 = HomebrewSchemaAdapter.parseSemanticVersion("Homebrew 4.4.2")
        XCTAssertEqual(v2?.major, 4)
        XCTAssertEqual(v2?.minor, 4)
        XCTAssertEqual(v2?.patch, 2)
    }

    func testIsVersionCompatible() {
        XCTAssertTrue(HomebrewSchemaAdapter.isVersionCompatible("Homebrew 5.0.0"))
        XCTAssertTrue(HomebrewSchemaAdapter.isVersionCompatible("Homebrew 4.3.1"))
        XCTAssertFalse(HomebrewSchemaAdapter.isVersionCompatible("Homebrew 3.6.0"))
    }
}
