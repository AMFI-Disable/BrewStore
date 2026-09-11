import AppKit
@testable import BrewStore
import XCTest

@MainActor
final class WindowFrameManagerTests: XCTestCase {
    private var testWindow: NSWindow!
    private let testAutosaveName = BrewStoreWindowFrameManager.autosaveName
    private let testSavedFrameKey = BrewStoreWindowFrameManager.savedFrameKey

    override func setUp() {
        super.setUp()
        testWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
    }

    override func tearDown() {
        testWindow.orderOut(nil)
        testWindow = nil
        UserDefaults.standard.removeObject(forKey: testSavedFrameKey)
        UserDefaults.standard.removeObject(forKey: BrewStoreWindowFrameManager.savedWidthKey)
        UserDefaults.standard.removeObject(forKey: BrewStoreWindowFrameManager.savedHeightKey)
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(testAutosaveName)")
        super.tearDown()
    }

    func testWindowFrameManagerConfiguration() {
        XCTAssertEqual(BrewStoreWindowFrameManager.minWidth, 860)
        XCTAssertEqual(BrewStoreWindowFrameManager.minHeight, 560)
        XCTAssertEqual(BrewStoreWindowFrameManager.defaultWidth, 1080)
        XCTAssertEqual(BrewStoreWindowFrameManager.defaultHeight, 720)
        XCTAssertEqual(BrewStoreWindowFrameManager.autosaveName, "BrewStoreMainWindow")
    }

    func testSaveAndRestoreFrame() {
        let manager = BrewStoreWindowFrameManager.shared
        testWindow.setFrame(NSRect(x: 200, y: 150, width: 1350, height: 850), display: false)

        manager.saveFrame(for: testWindow)

        // Verify saved to user defaults
        let savedDescriptor = UserDefaults.standard.string(forKey: testSavedFrameKey)
        XCTAssertNotNil(savedDescriptor)
        let savedWidth = UserDefaults.standard.double(forKey: BrewStoreWindowFrameManager.savedWidthKey)
        let savedHeight = UserDefaults.standard.double(forKey: BrewStoreWindowFrameManager.savedHeightKey)
        XCTAssertEqual(savedWidth, 1350, accuracy: 1.0)
        XCTAssertEqual(savedHeight, 850, accuracy: 1.0)

        // Create a new window with default size and restore
        let secondWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { secondWindow.orderOut(nil) }

        let restored = manager.restoreFrame(for: secondWindow)
        XCTAssertTrue(restored)
        XCTAssertEqual(secondWindow.frame.width, 1350, accuracy: 2.0)
        XCTAssertEqual(secondWindow.frame.height, 850, accuracy: 2.0)
    }

    func testSanitizeFrameEnforcesMinimumBounds() {
        let manager = BrewStoreWindowFrameManager.shared
        let tinyRect = NSRect(x: 100, y: 100, width: 400, height: 300)
        let sanitized = manager.sanitizeFrame(tinyRect)

        XCTAssertGreaterThanOrEqual(sanitized.width, BrewStoreWindowFrameManager.minWidth)
        XCTAssertGreaterThanOrEqual(sanitized.height, BrewStoreWindowFrameManager.minHeight)
    }

    func testSanitizeFrameRecoversFromOffScreenCoordinates() {
        let manager = BrewStoreWindowFrameManager.shared
        // Way out in negative or excessive space
        let offscreenRect = NSRect(x: -5000, y: -5000, width: 1200, height: 800)
        let sanitized = manager.sanitizeFrame(offscreenRect)

        if let screen = NSScreen.main {
            XCTAssertGreaterThanOrEqual(sanitized.minX, screen.visibleFrame.minX)
            XCTAssertGreaterThanOrEqual(sanitized.minY, screen.visibleFrame.minY)
            XCTAssertLessThanOrEqual(sanitized.maxX, screen.visibleFrame.maxX)
            XCTAssertLessThanOrEqual(sanitized.maxY, screen.visibleFrame.maxY)
        }
    }

    func testAttachAndDetachLifecycle() {
        let manager = BrewStoreWindowFrameManager.shared
        manager.attach(to: testWindow)

        // Resizing window should trigger automatic frame save
        testWindow.setFrame(NSRect(x: 150, y: 120, width: 1100, height: 750), display: false)
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: testWindow)

        let savedDescriptor = UserDefaults.standard.string(forKey: testSavedFrameKey)
        XCTAssertNotNil(savedDescriptor)

        manager.detach()
    }
}
