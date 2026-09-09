@testable import BrewStore
import Foundation
import XCTest

final class CellarScannerTests: XCTestCase {
    func testScanInstalledFormulaeWithReceipt() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cellar = tempDir.appendingPathComponent("Cellar")
        let toolDir = cellar.appendingPathComponent("my-tool/1.2.3")
        try FileManager.default.createDirectory(at: toolDir, withIntermediateDirectories: true)

        let receiptJSON = """
        {
          "homebrew_version": "4.3.0",
          "runtime_dependencies": [
            { "full_name": "openssl@3" },
            { "full_name": "readline" }
          ],
          "source": {
            "tap": "homebrew/core",
            "versions": { "stable": "1.2.3" }
          }
        }
        """
        try receiptJSON.data(using: .utf8)?.write(to: toolDir.appendingPathComponent("INSTALL_RECEIPT.json"))

        let records = CellarScanner.scanInstalledFormulae(cellarPath: cellar.path)
        XCTAssertEqual(records.count, 1)

        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.id, "my-tool")
        XCTAssertEqual(record.version, "1.2.3")
        XCTAssertEqual(record.kind, .formula)
        XCTAssertEqual(record.dependencies, ["openssl@3", "readline"])
        XCTAssertEqual(record.tap, "homebrew/core")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testScanInstalledCasks() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let caskroom = tempDir.appendingPathComponent("Caskroom")
        let appDir = caskroom.appendingPathComponent("sample-editor/2.5.0")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        let records = CellarScanner.scanInstalledCasks(caskroomPath: caskroom.path)
        XCTAssertEqual(records.count, 1)

        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.id, "sample-editor")
        XCTAssertEqual(record.version, "2.5.0")
        XCTAssertEqual(record.kind, .cask)

        let map = CellarScanner.toAuthoritativeMap(records)
        XCTAssertEqual(map["sample-editor"], "2.5.0")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testScanAllInstalledCombinesFormulaeAndCasks() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cellar = tempDir.appendingPathComponent("Cellar/git/2.45.0")
        let caskroom = tempDir.appendingPathComponent("Caskroom/iterm2/3.5.0")
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)

        let (formulae, casks) = CellarScanner.scanAllInstalled(prefix: tempDir.path)
        XCTAssertEqual(formulae.count, 1)
        XCTAssertEqual(formulae.first?.id, "git")
        XCTAssertEqual(casks.count, 1)
        XCTAssertEqual(casks.first?.id, "iterm2")

        try? FileManager.default.removeItem(at: tempDir)
    }
}
