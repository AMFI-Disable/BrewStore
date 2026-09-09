@testable import BrewStore
import Foundation
import XCTest

final class MASReceiptScannerTests: XCTestCase {
    func testScanInstalledAppStoreAppsWithReceipt() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appsDir = tempDir.appendingPathComponent("Applications")
        let appBundle = appsDir.appendingPathComponent("SampleNotes.app")
        let contents = appBundle.appendingPathComponent("Contents")
        let receiptDir = contents.appendingPathComponent("_MASReceipt")

        try FileManager.default.createDirectory(at: receiptDir, withIntermediateDirectories: true)

        // Write dummy receipt file
        try "RECEIPT_BINARY_PAYLOAD".data(using: .utf8)?.write(to: receiptDir.appendingPathComponent("receipt"))

        // Write Info.plist
        let plistDict: [String: Any] = [
            "CFBundleDisplayName": "Sample Notes",
            "CFBundleIdentifier": "com.example.samplenotes",
            "CFBundleShortVersionString": "2.4.1"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        // Also create a non-MAS app in the same dir
        let regularApp = appsDir.appendingPathComponent("RegularTool.app/Contents")
        try FileManager.default.createDirectory(at: regularApp, withIntermediateDirectories: true)
        let regularPlist: [String: Any] = ["CFBundleName": "Regular Tool", "CFBundleIdentifier": "com.example.regular"]
        let regData = try PropertyListSerialization.data(fromPropertyList: regularPlist, format: .xml, options: 0)
        try regData.write(to: regularApp.appendingPathComponent("Info.plist"))

        let scanned = MASReceiptScanner.scanInstalledAppStoreApps(directories: [appsDir.path])
        XCTAssertEqual(scanned.count, 1)

        let record = try XCTUnwrap(scanned.first)
        XCTAssertEqual(record.name, "Sample Notes")
        XCTAssertEqual(record.bundleIdentifier, "com.example.samplenotes")
        XCTAssertEqual(record.installedVersion, "2.4.1")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAppWithoutReceiptIgnored() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appsDir = tempDir.appendingPathComponent("Applications")
        let appBundle = appsDir.appendingPathComponent("VanillaApp.app/Contents")
        try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)

        let scanned = MASReceiptScanner.scanInstalledAppStoreApps(directories: [appsDir.path])
        XCTAssertTrue(scanned.isEmpty)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
