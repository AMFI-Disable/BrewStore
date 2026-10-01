import AppKit
@testable import BrewStore
import XCTest

@MainActor
final class WindowManagerTests: XCTestCase {
    private var testWindow1: NSWindow!
    private var testWindow2: NSWindow!

    override func setUp() {
        super.setUp()
        BrewStoreWindowManager.shared.resetForTesting()
        testWindow1 = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        testWindow1.isReleasedWhenClosed = false
        testWindow2 = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        testWindow2.isReleasedWhenClosed = false
        BrewStorePreferences.shared.hideDockIconWhenWindowClosed = false
    }

    override func tearDown() {
        testWindow1?.orderOut(nil)
        testWindow2?.orderOut(nil)
        testWindow1 = nil
        testWindow2 = nil
        BrewStorePreferences.shared.hideDockIconWhenWindowClosed = false
        BrewStoreWindowManager.shared.resetForTesting()
        super.tearDown()
    }

    func testAttachPrimaryWindow() {
        let manager = BrewStoreWindowManager.shared
        manager.attach(to: testWindow1)

        XCTAssertEqual(manager.mainWindow, testWindow1)
        XCTAssertEqual(testWindow1.identifier?.rawValue, "BrewStoreMainWindow")
        XCTAssertTrue(testWindow1.delegate === manager)
    }

    func testDeduplicationRejectsSecondWindow() {
        let manager = BrewStoreWindowManager.shared
        testWindow1.makeKeyAndOrderFront(nil)
        manager.attach(to: testWindow1)

        XCTAssertEqual(manager.mainWindow, testWindow1)

        // Attempt to attach a second window while the first is active in NSApp.windows
        testWindow2.makeKeyAndOrderFront(nil)
        manager.attach(to: testWindow2)

        // mainWindow must remain testWindow1, and testWindow2 must be closed/ordered out
        XCTAssertEqual(manager.mainWindow, testWindow1)
        XCTAssertFalse(testWindow2.isVisible)
    }

    func testIgnoreSpecialWindows() {
        let manager = BrewStoreWindowManager.shared
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { panel.orderOut(nil) }

        XCTAssertTrue(manager.isPanelOrSpecial(panel))
        manager.attach(to: panel)
        XCTAssertNotEqual(manager.mainWindow, panel)
    }

    func testWindowShouldCloseWithHidePreference() {
        let manager = BrewStoreWindowManager.shared
        manager.attach(to: testWindow1)
        testWindow1.makeKeyAndOrderFront(nil)

        // With hide preference enabled: window should NOT close, but order out
        BrewStorePreferences.shared.hideDockIconWhenWindowClosed = true
        let shouldClose = manager.windowShouldClose(testWindow1)

        XCTAssertFalse(shouldClose)
        XCTAssertFalse(testWindow1.isVisible)

        // Reopening brings it back
        manager.showMainWindow()
        XCTAssertTrue(testWindow1.isVisible)
    }

    func testWindowShouldCloseWhenAppTerminating() {
        let manager = BrewStoreWindowManager.shared
        manager.attach(to: testWindow1)
        BrewStorePreferences.shared.hideDockIconWhenWindowClosed = true

        // When terminating, must allow close
        manager.isAppTerminating = true
        let shouldClose = manager.windowShouldClose(testWindow1)
        XCTAssertTrue(shouldClose)
    }

    func testWindowWillCloseClearsMainWindow() {
        let manager = BrewStoreWindowManager.shared
        manager.attach(to: testWindow1)
        XCTAssertEqual(manager.mainWindow, testWindow1)

        let notification = Notification(
            name: NSWindow.willCloseNotification,
            object: testWindow1,
            userInfo: nil
        )
        manager.windowWillClose(notification)

        XCTAssertNil(manager.mainWindow)
    }

    func testEnforcesWindowTabbingDisallowed() {
        let manager = BrewStoreWindowManager.shared
        manager.attach(to: testWindow1)

        XCTAssertEqual(testWindow1.tabbingMode, .disallowed)
    }

    func testHasActiveOrHiddenMainWindow() {
        let manager = BrewStoreWindowManager.shared
        XCTAssertFalse(manager.hasActiveOrHiddenMainWindow)

        manager.attach(to: testWindow1)
        XCTAssertTrue(manager.hasActiveOrHiddenMainWindow)

        // Even when ordered out / hidden, it still reports active/hidden window
        testWindow1.orderOut(nil)
        XCTAssertTrue(manager.hasActiveOrHiddenMainWindow)

        // Clear window
        let notification = Notification(
            name: NSWindow.willCloseNotification,
            object: testWindow1,
            userInfo: nil
        )
        manager.windowWillClose(notification)
        XCTAssertFalse(manager.hasActiveOrHiddenMainWindow)
    }

    func testSafeExplicitDelegateForwarding() {
        let manager = BrewStoreWindowManager.shared
        let mockDelegate = MockWindowDelegate()
        testWindow1.delegate = mockDelegate

        manager.attach(to: testWindow1)

        let notif = Notification(name: NSWindow.didBecomeKeyNotification, object: testWindow1)
        manager.windowDidBecomeKey(notif)
        XCTAssertTrue(mockDelegate.didBecomeKeyCalled)

        manager.windowDidResignKey(notif)
        XCTAssertTrue(mockDelegate.didResignKeyCalled)

        manager.windowDidResize(notif)
        XCTAssertTrue(mockDelegate.didResizeCalled)

        manager.windowDidMove(notif)
        XCTAssertTrue(mockDelegate.didMoveCalled)

        manager.windowDidMiniaturize(notif)
        XCTAssertTrue(mockDelegate.didMiniaturizeCalled)

        manager.windowDidDeminiaturize(notif)
        XCTAssertTrue(mockDelegate.didDeminiaturizeCalled)

        _ = manager.windowShouldClose(testWindow1)
        XCTAssertTrue(mockDelegate.shouldCloseCalled)

        manager.windowWillClose(notif)
        XCTAssertTrue(mockDelegate.willCloseCalled)
    }

    func testShowMainWindowWithoutExistingWindowDoesNotCrash() {
        let manager = BrewStoreWindowManager.shared
        manager.showMainWindow()
        if let window = manager.mainWindow {
            XCTAssertFalse(manager.isPanelOrSpecial(window))
        }
    }
}

private final class MockWindowDelegate: NSObject, NSWindowDelegate {
    var didBecomeKeyCalled = false
    var didResignKeyCalled = false
    var didResizeCalled = false
    var didMoveCalled = false
    var didMiniaturizeCalled = false
    var didDeminiaturizeCalled = false
    var willCloseCalled = false
    var shouldCloseCalled = false

    func windowDidBecomeKey(_: Notification) { didBecomeKeyCalled = true }
    func windowDidResignKey(_: Notification) { didResignKeyCalled = true }
    func windowDidResize(_: Notification) { didResizeCalled = true }
    func windowDidMove(_: Notification) { didMoveCalled = true }
    func windowDidMiniaturize(_: Notification) { didMiniaturizeCalled = true }
    func windowDidDeminiaturize(_: Notification) { didDeminiaturizeCalled = true }
    func windowWillClose(_: Notification) { willCloseCalled = true }
    func windowShouldClose(_: NSWindow) -> Bool {
        shouldCloseCalled = true
        return true
    }
}
