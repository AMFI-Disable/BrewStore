import AppKit
@testable import BrewStore
import XCTest

@MainActor
final class MenuBarDistortionPreventionTests: XCTestCase {
    func testMenuBarPanelDimensionsAreRigidAndPositive() {
        XCTAssertEqual(BrewStoreMenuBarCompanionManager.panelWidth, 360)
        XCTAssertEqual(BrewStoreMenuBarCompanionManager.panelHeight, 440)
        XCTAssertEqual(BrewStoreMenuBarCompanionManager.compactPanelHeight, 360)
        XCTAssertGreaterThan(BrewStoreMenuBarCompanionManager.panelHeight, BrewStoreMenuBarCompanionManager.compactPanelHeight)
    }

    func testMenuBarWindowDetection() {
        let manager = BrewStoreMenuBarCompanionManager.shared

        let regularWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        XCTAssertFalse(manager.isMenuBarWindow(regularWindow))

        let panelWindow = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // NSPanel className contains "Panel", but check custom identifiers or popover class strings
        XCTAssertFalse(manager.isMenuBarWindow(panelWindow))
    }

    func testConfigureMenuBarWindowEnforcesRigidGeometryAndNoResizeAnimation() {
        let manager = BrewStoreMenuBarCompanionManager.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )

        // Standard configuration
        manager.configureMenuBarWindow(window, isCompact: false)

        XCTAssertFalse(window.isMovable)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertEqual(window.animationBehavior, .none)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize, NSSize(width: 360, height: 440))
        XCTAssertEqual(window.maxSize, NSSize(width: 360, height: 440))
        XCTAssertTrue(window.hasShadow)

        // Compact configuration
        manager.configureMenuBarWindow(window, isCompact: true)
        XCTAssertEqual(window.minSize, NSSize(width: 360, height: 360))
        XCTAssertEqual(window.maxSize, NSSize(width: 360, height: 360))
    }

    func testMenuBarTitleStateReporting() {
        let companion = BrewStoreMenuBarCompanionManager.shared

        let operatingTitle = companion.menuBarTitle(outdatedCount: 5, isOperating: true)
        XCTAssertEqual(operatingTitle, "⏳ BrewStore…")

        let outdatedTitle = companion.menuBarTitle(outdatedCount: 3, isOperating: false)
        XCTAssertEqual(outdatedTitle, "🍺 BrewStore (3)")

        let cleanTitle = companion.menuBarTitle(outdatedCount: 0, isOperating: false)
        XCTAssertEqual(cleanTitle, "🍺 BrewStore")
    }

    func testMenuBarPreferencesToggling() {
        let prefs = BrewStorePreferences.shared
        prefs.resetToDefaults()

        XCTAssertFalse(prefs.compactMenuBarView)
        XCTAssertFalse(prefs.menuBarCloseOnAction)

        prefs.compactMenuBarView = true
        XCTAssertTrue(prefs.compactMenuBarView)

        prefs.menuBarCloseOnAction = true
        XCTAssertTrue(prefs.menuBarCloseOnAction)

        prefs.resetToDefaults()
        XCTAssertFalse(prefs.compactMenuBarView)
        XCTAssertFalse(prefs.menuBarCloseOnAction)
    }
}
