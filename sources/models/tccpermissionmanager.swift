import AppKit
import Foundation

enum TCCPermissionKind: String, CaseIterable, Sendable, Identifiable {
    case systemExtensions = "System Extension / Network Filter"
    case accessibility = "Accessibility & Window Control"
    case fullDiskAccess = "Full Disk Access"
    case inputMonitoring = "Input Monitoring"
    case screenRecording = "Screen Recording"

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .systemExtensions: "shield.lefthalf.filled"
        case .accessibility: "figure.roll"
        case .fullDiskAccess: "internaldrive.fill"
        case .inputMonitoring: "keyboard.fill"
        case .screenRecording: "record.circle.fill"
        }
    }

    var explanation: String {
        switch self {
        case .systemExtensions:
            "This application installs low-level network filters or system drivers that must be allowed under macOS System Settings."
        case .accessibility:
            "This application controls windows, menus, or system shortcuts and requires Accessibility authorization."
        case .fullDiskAccess:
            "This application manages, backs up, or indexes files across your user account and requires Full Disk Access."
        case .inputMonitoring:
            "This application listens to system-wide keyboard shortcuts or mouse events."
        case .screenRecording:
            "This application captures screen content, video streams, or desktop screenshots."
        }
    }

    var settingsURLString: String {
        switch self {
        case .systemExtensions:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SystemExtensions"
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .fullDiskAccess:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
    }
}

final class TCCPermissionManager: Sendable {
    static let shared = TCCPermissionManager()

    /// Detects if a package requires macOS TCC or System Extension permissions based on its caveats and metadata.
    func detectPermissions(for package: BrewStorePackage) -> [TCCPermissionKind] {
        guard package.kind == .cask else { return [] }
        var result: [TCCPermissionKind] = []

        let text = "\(package.caveats ?? "") \(package.description)".lowercased()

        if text.contains("system extension") || text.contains("network extension") || text.contains("kext") || text.contains("kernel extension") {
            result.append(.systemExtensions)
        }
        if text.contains("accessibility") || text.contains("axui") || text.contains("control your computer") {
            result.append(.accessibility)
        }
        if text.contains("full disk access") || text.contains("fda") {
            result.append(.fullDiskAccess)
        }
        if text.contains("input monitoring") || text.contains("keystroke") {
            result.append(.inputMonitoring)
        }
        if text.contains("screen recording") || text.contains("screen capture") {
            result.append(.screenRecording)
        }

        return result
    }

    /// Opens the corresponding macOS System Settings pane for the given permission kind.
    @MainActor
    func openSystemSettings(for permission: TCCPermissionKind) {
        guard let url = URL(string: permission.settingsURLString) else { return }
        if NSWorkspace.shared.open(url) {
            return
        }
        // Fallback to general Privacy & Security pane
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
