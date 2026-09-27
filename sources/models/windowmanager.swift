import AppKit
import Foundation

@MainActor
final class BrewStoreWindowManager: NSObject, NSWindowDelegate, @unchecked Sendable {
    static let shared = BrewStoreWindowManager()

    private(set) weak var mainWindow: NSWindow?
    private weak var systemDelegate: NSWindowDelegate?
    private var lastReopenTimestamp: TimeInterval = 0
    var isAppTerminating = false

    override private init() {
        super.init()
    }

    func resetForTesting() {
        mainWindow = nil
        systemDelegate = nil
        lastReopenTimestamp = 0
        isAppTerminating = false
    }

    @discardableResult
    func register(window: NSWindow) -> Bool {
        guard !isPanelOrSpecial(window) else { return true }

        // Deduplication check: if we already have an active main window
        // and a different window attempts to attach, close the duplicate immediately
        // and bring the primary window to front.
        if let existing = mainWindow, existing !== window {
            window.isReleasedWhenClosed = false
            window.orderOut(nil)
            DispatchQueue.main.async {
                window.delegate = nil
                window.close()
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

        // Debounced fallback to trigger window creation if no window exists
        reopenWindowDebounced()
    }

    private func reopenWindowDebounced() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastReopenTimestamp > 1.0 else { return }
        lastReopenTimestamp = now

        if let openURL = URL(string: "brewstore://open") {
            NSWorkspace.shared.open(openURL)
        }
    }

    // MARK: - Forwarding Unknown Delegate Methods

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return systemDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let systemDelegate, systemDelegate.responds(to: aSelector) {
            return systemDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }

    // MARK: - NSWindowDelegate

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
            mainWindow = nil
        }
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
