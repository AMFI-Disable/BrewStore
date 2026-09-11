import AppKit
import Foundation

@MainActor
final class BrewStoreWindowFrameManager: NSObject, @unchecked Sendable {
    static let shared = BrewStoreWindowFrameManager()

    static let autosaveName: NSWindow.FrameAutosaveName = "BrewStoreMainWindow"
    static let savedFrameKey = "BrewStoreMainWindowSavedFrame"
    static let savedWidthKey = "BrewStoreMainWindowWidth"
    static let savedHeightKey = "BrewStoreMainWindowHeight"

    static let minWidth: CGFloat = 860
    static let minHeight: CGFloat = 560
    static let defaultWidth: CGFloat = 1080
    static let defaultHeight: CGFloat = 720

    private weak var currentWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    override private init() {
        super.init()
    }

    func attach(to window: NSWindow) {
        guard currentWindow !== window else { return }
        detach()
        currentWindow = window

        // Initial restore
        _ = restoreFrame(for: window)

        // Deferred restore to override initial SwiftUI defaultSize pass if needed
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            _ = self.restoreFrame(for: window)
        }

        let center = NotificationCenter.default

        let resizeObs = center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.saveFrame(for: window)
        }

        let moveObs = center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.saveFrame(for: window)
        }

        let closeObs = center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.saveFrame(for: window)
        }

        let termObs = center.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.saveFrame(for: window)
        }

        observers = [resizeObs, moveObs, closeObs, termObs]
    }

    func detach() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        currentWindow = nil
    }

    @discardableResult
    func restoreFrame(for window: NSWindow) -> Bool {
        guard !window.styleMask.contains(.fullScreen) else { return false }

        window.minSize = NSSize(width: Self.minWidth, height: Self.minHeight)
        window.setFrameAutosaveName(Self.autosaveName)

        // 1. Try standard AppKit frame restoration
        if window.setFrameUsingName(Self.autosaveName) {
            let sanitized = sanitizeFrame(window.frame)
            if sanitized != window.frame {
                window.setFrame(sanitized, display: true, animate: false)
            }
            return true
        }

        // 2. Try explicit NSRect string descriptor from UserDefaults
        if let savedString = UserDefaults.standard.string(forKey: Self.savedFrameKey) {
            let rect = NSRectFromString(savedString)
            if rect.width >= Self.minWidth, rect.height >= Self.minHeight {
                let sanitized = sanitizeFrame(rect)
                window.setFrame(sanitized, display: true, animate: false)
                return true
            }
        }

        // 3. Try explicit width and height values
        let savedWidth = UserDefaults.standard.double(forKey: Self.savedWidthKey)
        let savedHeight = UserDefaults.standard.double(forKey: Self.savedHeightKey)
        if savedWidth >= Double(Self.minWidth), savedHeight >= Double(Self.minHeight) {
            let targetSize = NSSize(width: CGFloat(savedWidth), height: CGFloat(savedHeight))
            let currentOrigin = window.frame.origin
            let rect = NSRect(origin: currentOrigin, size: targetSize)
            let sanitized = sanitizeFrame(rect)
            window.setFrame(sanitized, display: true, animate: false)
            return true
        }

        return false
    }

    func saveFrame(for window: NSWindow) {
        guard !window.isMiniaturized, !window.styleMask.contains(.fullScreen) else { return }
        let frame = window.frame
        guard frame.width >= Self.minWidth, frame.height >= Self.minHeight else { return }

        window.saveFrame(usingName: Self.autosaveName)
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.savedFrameKey)
        UserDefaults.standard.set(Double(frame.width), forKey: Self.savedWidthKey)
        UserDefaults.standard.set(Double(frame.height), forKey: Self.savedHeightKey)
    }

    func sanitizeFrame(_ rect: NSRect) -> NSRect {
        var target = rect

        let screen = NSScreen.screens.first { $0.frame.intersects(target) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return target }

        let visible = screen.visibleFrame

        target.size.width = min(max(target.width, Self.minWidth), visible.width)
        target.size.height = min(max(target.height, Self.minHeight), visible.height)

        if target.maxX > visible.maxX {
            target.origin.x = max(visible.origin.x, visible.maxX - target.width)
        }
        if target.minX < visible.minX {
            target.origin.x = visible.minX
        }
        if target.maxY > visible.maxY {
            target.origin.y = max(visible.origin.y, visible.maxY - target.height)
        }
        if target.minY < visible.minY {
            target.origin.y = visible.minY
        }

        return target
    }
}
