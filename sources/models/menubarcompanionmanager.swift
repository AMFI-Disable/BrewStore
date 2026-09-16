import AppKit
import SwiftUI

@MainActor
final class BrewStoreMenuBarCompanionManager: ObservableObject {
    static let shared = BrewStoreMenuBarCompanionManager()

    static let panelWidth: CGFloat = 360
    static let panelHeight: CGFloat = 440
    static let compactPanelHeight: CGFloat = 360

    @Published var isEnabled = true

    func menuBarTitle(outdatedCount: Int, isOperating: Bool) -> String {
        if isOperating {
            return "⏳ BrewStore…"
        }
        if outdatedCount > 0 {
            return "🍺 BrewStore (\(outdatedCount))"
        }
        return "🍺 BrewStore"
    }

    func performQuickUpgrade(manager: HomebrewManager) {
        manager.upgradeAllPackages()
    }

    func closeMenuBarPanel() {
        for window in NSApp.windows {
            if isMenuBarWindow(window) {
                window.orderOut(nil)
            }
        }
    }

    func isMenuBarWindow(_ window: NSWindow) -> Bool {
        let className = window.className
        return className.contains("StatusBar") ||
            className.contains("MenuBar") ||
            className.contains("Popover") ||
            className.contains("NSPopoverWindow")
    }

    func configureMenuBarWindow(_ window: NSWindow, isCompact: Bool = false) {
        let targetHeight = isCompact ? Self.compactPanelHeight : Self.panelHeight
        let fixedSize = NSSize(width: Self.panelWidth, height: targetHeight)

        if window.isMovable {
            window.isMovable = false
        }
        if window.isMovableByWindowBackground {
            window.isMovableByWindowBackground = false
        }
        if window.animationBehavior != .none {
            window.animationBehavior = .none
        }
        if window.styleMask.contains(.resizable) {
            window.styleMask.remove(.resizable)
        }
        if !window.hasShadow {
            window.hasShadow = true
        }

        if window.minSize != fixedSize {
            window.minSize = fixedSize
        }
        if window.maxSize != fixedSize {
            window.maxSize = fixedSize
        }
        let widthDiff = abs(window.frame.width - fixedSize.width)
        let heightDiff = abs(window.frame.height - fixedSize.height)
        if widthDiff > 0.5 || heightDiff > 0.5 {
            let currentFrame = window.frame
            let newY = currentFrame.maxY - targetHeight
            let newFrame = NSRect(x: currentFrame.origin.x, y: newY, width: Self.panelWidth, height: targetHeight)
            window.setFrame(newFrame, display: false, animate: false)
        }
    }
}
