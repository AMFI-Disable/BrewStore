import AppKit
import Foundation

@MainActor
final class BrewStoreWindowManager: NSObject, NSWindowDelegate, @unchecked Sendable {
    static let shared = BrewStoreWindowManager()

    private(set) weak var mainWindow: NSWindow?
    private weak var systemDelegate: NSWindowDelegate?
    var isAppTerminating = false

    override private init() {
        super.init()
    }

    func resetForTesting() {
        mainWindow = nil
        systemDelegate = nil
        isAppTerminating = false
    }

    var hasActiveOrHiddenMainWindow: Bool {
        mainWindow != nil
    }

    @discardableResult
    func register(window: NSWindow) -> Bool {
        guard !isPanelOrSpecial(window) else { return true }

        // Enforce no window tabbing on all primary application windows
        window.tabbingMode = .disallowed

        // Deduplication check: if we already have an active main window
        // and a different window attempts to attach, hide the duplicate immediately
        // and bring the primary window to front.
        if let existing = mainWindow, existing !== window {
            window.isReleasedWhenClosed = false
            window.orderOut(nil)
            DispatchQueue.main.async {
                existing.makeKeyAndOrderFront(nil)
                existing.deminiaturize(nil)
            }
            return false
        }

        mainWindow = window
        window.identifier = NSUserInterfaceItemIdentifier("BrewStoreMainWindow")

        if window.delegate !== self {
            systemDelegate = window.delegate
            window.delegate = self
        }
        return true
    }

    func attach(to window: NSWindow) {
        _ = register(window: window)
    }

    func showMainWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            window.deminiaturize(nil)
            return
        }

        // Look for any existing non-special window in NSApp.windows
        let candidates = NSApp.windows.filter { !isPanelOrSpecial($0) }
        if let first = candidates.first {
            mainWindow = first
            first.makeKeyAndOrderFront(nil)
            first.deminiaturize(nil)
            return
        }
    }

    // MARK: - Safe Explicit NSWindowDelegate Forwarding

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isAppTerminating {
            return true
        }

        // Only hide the primary main window when the preference is active.
        // Secondary windows, sheets, panels, and duplicates must always be allowed to close.
        guard sender === mainWindow else {
            return systemDelegate?.windowShouldClose?(sender) ?? true
        }

        if BrewStorePreferences.shared.hideDockIconWhenWindowClosed {
            sender.orderOut(nil)
            BrewStoreDockLifecycleManager.shared.checkVisibleWindowsAndAdjustPolicy()
            return false // Hide the main window instead of destroying it
        }

        return systemDelegate?.windowShouldClose?(sender) ?? true
    }

    func windowWillClose(_ notification: Notification) {
        systemDelegate?.windowWillClose?(notification)
        if let win = notification.object as? NSWindow, win === mainWindow {
            win.identifier = nil
            mainWindow = nil
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        systemDelegate?.windowDidBecomeKey?(notification)
    }

    func windowDidResignKey(_ notification: Notification) {
        systemDelegate?.windowDidResignKey?(notification)
    }

    func windowDidResize(_ notification: Notification) {
        systemDelegate?.windowDidResize?(notification)
    }

    func windowDidMove(_ notification: Notification) {
        systemDelegate?.windowDidMove?(notification)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        systemDelegate?.windowDidMiniaturize?(notification)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        systemDelegate?.windowDidDeminiaturize?(notification)
    }

    func isPanelOrSpecial(_ window: NSWindow) -> Bool {
        window is NSPanel ||
            window.isSheet ||
            window.sheetParent != nil ||
            window.className.contains("StatusBar") ||
            window.className.contains("MenuBar") ||
            window.className.contains("Popover") ||
            window.className.contains("NSPopoverWindow") ||
            window.className.contains("Tooltip")
    }
}
