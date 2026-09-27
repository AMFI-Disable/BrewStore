import AppKit
import Foundation

@MainActor
final class BrewStoreDockLifecycleManager: NSObject, ObservableObject {
    static let shared = BrewStoreDockLifecycleManager()

    private var isObserving = false

    func setup() {
        guard !isObserving else { return }
        isObserving = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreferenceChange(_:)),
            name: .brewStoreDockLifecyclePreferenceDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBadgePreferenceChange(_:)),
            name: .brewStoreDockBadgePreferenceDidChange,
            object: nil
        )

        // SwiftUI creates the WindowGroup after applicationDidFinishLaunching.
        // Do not treat the temporarily empty NSApp.windows collection as a
        // closed-window state or switch to accessory mode before the main
        // window exists. Window-close and preference notifications perform
        // the policy check once the window lifecycle is established.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private var lastOutdatedCount: Int = 0

    func updateBadge(outdatedCount: Int) {
        lastOutdatedCount = outdatedCount
        guard BrewStorePreferences.shared.showDockBadge else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        if outdatedCount > 0 {
            NSApp.dockTile.badgeLabel = "\(outdatedCount)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    @objc private func handleBadgePreferenceChange(_: Notification) {
        updateBadge(outdatedCount: lastOutdatedCount)
    }

    @objc private func handleWindowWillClose(_ note: Notification) {
        guard BrewStorePreferences.shared.hideDockIconWhenWindowClosed else { return }
        guard let win = note.object as? NSWindow, !isPanelOrSpecial(win), win.canBecomeMain else { return }

        // Evaluate after window has closed in the current runloop cycle
        DispatchQueue.main.async { [weak self] in
            self?.checkVisibleWindowsAndAdjustPolicy()
        }
    }

    @objc private func handleWindowDidBecomeKey(_ note: Notification) {
        guard let win = note.object as? NSWindow, !isPanelOrSpecial(win), win.canBecomeMain else { return }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    @objc private func handlePreferenceChange(_: Notification) {
        checkVisibleWindowsAndAdjustPolicy()
    }

    func showMainWindowAndDock() {
        BrewStoreWindowManager.shared.showMainWindow()
    }

    func checkVisibleWindowsAndAdjustPolicy() {
        guard BrewStorePreferences.shared.hideDockIconWhenWindowClosed else {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            return
        }

        let visibleMainWindows = NSApp.windows.filter { win in
            win.isVisible && !isPanelOrSpecial(win)
        }

        if visibleMainWindows.isEmpty {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    func isPanelOrSpecial(_ window: NSWindow) -> Bool {
        BrewStoreWindowManager.shared.isPanelOrSpecial(window)
    }
}
